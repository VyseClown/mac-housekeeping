import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir, hostname, userInfo } from "node:os";
import { promisify } from "node:util";

import { buildMockSnapshot } from "@/lib/mock";
import {
  DEFAULT_PROTECTED_KEEPS,
  isProtectedPath,
  isProtectedProcess,
} from "@/lib/protect";
import { applySession } from "@/lib/session";
import type {
  CleanupItem,
  CleanupKind,
  HeldFile,
  OpenHandle,
  ProcessInfo,
  ProtectedKeep,
  SimulatorDevice,
  Snapshot,
} from "@/lib/types";
import { evaluatePathUsage, evaluateProcessUsage } from "@/lib/usage";

const execFileAsync = promisify(execFile);

export type SnapshotTab = "cleanup" | "processes" | "all";

export type CollectRequest = {
  tab?: SnapshotTab;
  force?: boolean;
};

const NAME_FILTER =
  /Simulator|launchd_sim|qemu-system|CoreSimulator|Xcode|SourceKit|ffmpeg|tcpdump|Preview|QuickTime|nightshift|ai-memory|ai_memory/i;

const CANDIDATE_MATCH =
  /investigation|repro-har|repro-screen|used-capture|used-export|used-review|already-used/i;

const CACHE_TTL_MS = 5000;

type CacheEntry = {
  at: number;
  snapshot: Snapshot;
  included: { cleanup: boolean; processes: boolean };
};

let inflight: Promise<Snapshot> | null = null;
let inflightIncludesProcesses = false;
let cache: CacheEntry | null = null;

function isDarwin(): boolean {
  if (process.env.HOUSEKEEPING_FORCE_MOCK === "1") return false;
  if (process.env.HOUSEKEEPING_FORCE_MAC === "1") return true;
  return process.platform === "darwin";
}

async function run(
  cmd: string,
  args: string[],
  timeoutMs = 8000
): Promise<{ stdout: string; ok: boolean }> {
  try {
    const { stdout } = await execFileAsync(cmd, args, {
      timeout: timeoutMs,
      maxBuffer: 8 * 1024 * 1024,
    });
    return { stdout: String(stdout), ok: true };
  } catch (error) {
    const err = error as { stdout?: string };
    return { stdout: String(err.stdout ?? ""), ok: false };
  }
}

function slug(path: string): string {
  return path
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(-48);
}

function kindFor(path: string): CleanupKind {
  return /used-capture|used-export|used-review|already-used|\.(mov|mp4|m4v|png|jpe?g|heic|webp)$/i.test(
    path
  )
    ? "used-media"
    : "investigation-leftover";
}

function noteFor(path: string, kind: CleanupKind): string {
  if (kind === "used-media") {
    return "Already-used image or video. Eligible only after usage validates idle.";
  }
  return "Investigation leftover. Eligible only after usage validates idle.";
}

async function pathBytes(path: string): Promise<number> {
  const { stdout, ok } = await run("du", ["-sk", path], 6000);
  if (!ok) return 0;
  const kb = Number.parseInt(stdout.trim().split(/\s+/)[0] ?? "", 10);
  return Number.isFinite(kb) ? kb * 1024 : 0;
}

async function lastAccessIso(path: string): Promise<string> {
  const mac = await run("stat", ["-f", "%a", path], 4000);
  if (mac.ok) {
    const seconds = Number.parseInt(mac.stdout.trim(), 10);
    if (Number.isFinite(seconds)) return new Date(seconds * 1000).toISOString();
  }
  const gnu = await run("stat", ["-c", "%X", path], 4000);
  if (gnu.ok) {
    const seconds = Number.parseInt(gnu.stdout.trim(), 10);
    if (Number.isFinite(seconds)) return new Date(seconds * 1000).toISOString();
  }
  return new Date(0).toISOString();
}

function parseHandleLines(stdout: string): Map<string, OpenHandle[]> {
  const handles = new Map<string, OpenHandle[]>();
  for (const line of stdout.split("\n").slice(1)) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 9) continue;
    const process = parts[0];
    const pid = Number.parseInt(parts[1] ?? "", 10);
    if (!Number.isFinite(pid)) continue;
    const name = parts.slice(8).join(" ");
    if (!name.startsWith("/")) continue;
    const list = handles.get(name) ?? [];
    list.push({
      pid,
      process,
      fd: parts[3] ?? null,
      mode: parts[4] ?? null,
    });
    handles.set(name, list);
  }
  return handles;
}

async function handlesForPaths(paths: string[]): Promise<Map<string, OpenHandle[]>> {
  const map = new Map<string, OpenHandle[]>();
  if (paths.length === 0) return map;
  for (let index = 0; index < paths.length; index += 24) {
    const chunk = paths.slice(index, index + 24);
    const { stdout, ok } = await run("lsof", ["-nP", "--", ...chunk], 8000);
    if (!ok || !stdout.trim()) continue;
    const parsed = parseHandleLines(stdout);
    for (const path of chunk) {
      const exact = parsed.get(path) ?? [];
      const prefixed: OpenHandle[] = [];
      for (const [name, list] of parsed) {
        if (name === path || name.startsWith(path) || path.startsWith(name)) {
          prefixed.push(...list);
        }
      }
      map.set(path, exact.length > 0 ? exact : prefixed);
    }
  }
  return map;
}

async function findOn(roots: string[], maxdepth: number): Promise<string[]> {
  if (roots.length === 0) return [];
  const { stdout } = await run(
    "find",
    [
      ...roots,
      "-maxdepth",
      String(maxdepth),
      "(",
      "-iname",
      "*investigation*",
      "-o",
      "-iname",
      "*repro-har*",
      "-o",
      "-iname",
      "*repro-screen*",
      "-o",
      "-iname",
      "*used-capture*",
      "-o",
      "-iname",
      "*used-export*",
      "-o",
      "-iname",
      "*used-review*",
      "-o",
      "-iname",
      "*already-used*",
      ")",
    ],
    10000
  );
  return stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

async function findCandidates(home: string): Promise<string[]> {
  const mainRoots = [
    `${home}/Downloads`,
    `${home}/Desktop`,
    `${home}/Documents`,
    `${home}/Movies`,
    `${home}/Pictures`,
    "/tmp",
  ].filter((root) => existsSync(root));
  const derived = `${home}/Library/Developer/Xcode/DerivedData`;

  const [main, extra] = await Promise.all([
    findOn(mainRoots, 4),
    existsSync(derived) ? findOn([derived], 2) : Promise.resolve([]),
  ]);

  const seen = new Set<string>();
  const paths: string[] = [];
  for (const path of [...main, ...extra]) {
    if (!path || seen.has(path)) continue;
    if (!CANDIDATE_MATCH.test(path)) continue;
    seen.add(path);
    paths.push(path);
  }
  return paths;
}

async function mapPool<T, R>(
  items: T[],
  limit: number,
  work: (item: T) => Promise<R>
): Promise<R[]> {
  if (items.length === 0) return [];
  const results = new Array<R>(items.length);
  let next = 0;
  async function worker() {
    for (;;) {
      const index = next;
      if (index >= items.length) return;
      next += 1;
      results[index] = await work(items[index]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker())
  );
  return results;
}

function keepsFromFound(home: string, found: string[]): ProtectedKeep[] {
  const keeps: ProtectedKeep[] = DEFAULT_PROTECTED_KEEPS.map((keep) => {
    const path = keep.path.replace("/Users/alessandro", home);
    return {
      ...keep,
      path,
      present: existsSync(path),
    };
  });
  for (const path of found) {
    if (!isProtectedPath(path)) continue;
    if (keeps.some((keep) => keep.path === path)) continue;
    keeps.push({
      path,
      label: /nightshift/i.test(path) ? "nightshift" : "ai-memory",
      reason: "Installed on purpose. Never a cleanup candidate.",
      present: true,
    });
  }
  return keeps;
}

async function collectCleanup(
  home: string,
  warnings: string[]
): Promise<{ items: CleanupItem[]; keeps: ProtectedKeep[] }> {
  const found = await findCandidates(home);
  const keeps = keepsFromFound(home, found);
  const candidates = found.filter((path) => !isProtectedPath(path));
  const handleMap = await handlesForPaths(candidates);
  const items = await mapPool(candidates, 4, async (path) => {
    const [bytes, lastAccessAt] = await Promise.all([
      pathBytes(path),
      lastAccessIso(path),
    ]);
    const openHandles = handleMap.get(path) ?? [];
    const kind = kindFor(path);
    const usage = evaluatePathUsage({
      openHandles,
      lastAccessAt,
      protectedPath: false,
    });
    return {
      id: slug(path),
      path,
      kind,
      bytes,
      lastAccessAt,
      lastAccessSource: "stat" as const,
      openHandles,
      usage: usage.usage,
      usageReason: usage.usageReason,
      note: noteFor(path, kind),
    };
  });

  if (found.length === 0) {
    warnings.push(
      "No investigation leftovers or used-media folders matched on this Mac."
    );
  }

  return { items, keeps };
}

function parsePsLine(line: string): {
  pid: number;
  ppid: number;
  user: string;
  cpu: number;
  memMb: number;
  elapsed: string;
  state: string;
  command: string;
} | null {
  const match = line.trim().match(
    /^(\d+)\s+(\d+)\s+(\S+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$/
  );
  if (!match) return null;
  return {
    pid: Number(match[1]),
    ppid: Number(match[2]),
    user: match[3],
    cpu: Number(match[4]),
    memMb: Math.round(Number(match[6]) / 1024),
    elapsed: match[7],
    state: match[8],
    command: match[9],
  };
}

function processName(command: string): string {
  const base = command.split(" ")[0] ?? command;
  return base.split("/").pop() || command;
}

function categoryFor(name: string, command: string): ProcessInfo["category"] {
  if (isProtectedProcess(name, command)) return "protected";
  if (/Simulator|launchd_sim|qemu-system|CoreSimulator/i.test(name + command)) {
    return "simulator";
  }
  if (/Xcode|SourceKit/i.test(name + command)) return "xcode";
  if (/ffmpeg|tcpdump/i.test(name + command)) return "idle-leftover";
  return "dev";
}

async function filesForPids(
  pids: number[],
  cleanupPaths: string[]
): Promise<Map<number, HeldFile[]>> {
  const held = new Map<number, HeldFile[]>();
  if (pids.length === 0) return held;
  for (let index = 0; index < pids.length; index += 32) {
    const chunk = pids.slice(index, index + 32);
    const { stdout, ok } = await run(
      "lsof",
      ["-nP", "-p", chunk.join(",")],
      8000
    );
    if (!ok) continue;
    const seen = new Map<number, Set<string>>();
    for (const line of stdout.split("\n").slice(1)) {
      const parts = line.trim().split(/\s+/);
      if (parts.length < 9) continue;
      const pid = Number.parseInt(parts[1] ?? "", 10);
      const path = parts.slice(8).join(" ");
      if (!Number.isFinite(pid) || !path.startsWith("/")) continue;
      if (seen.get(pid)?.has(path)) continue;
      if (
        !CANDIDATE_MATCH.test(path) &&
        !isProtectedPath(path) &&
        !/CoreSimulator|DerivedData|worktree/i.test(path)
      ) {
        continue;
      }
      const already = seen.get(pid) ?? new Set<string>();
      already.add(path);
      seen.set(pid, already);
      const role: HeldFile["role"] = isProtectedPath(path)
        ? "protected"
        : cleanupPaths.some(
            (candidate) => path.startsWith(candidate) || candidate.startsWith(path)
          )
          ? "cleanup-target"
          : /CoreSimulator|DerivedData|worktree/i.test(path)
            ? "runtime"
            : "other";
      const list = held.get(pid) ?? [];
      if (list.length >= 6) continue;
      list.push({ path, role, bytes: null });
      held.set(pid, list);
    }
  }
  return held;
}

function buildProcesses(
  rows: NonNullable<ReturnType<typeof parsePsLine>>[],
  heldByPid: Map<number, HeldFile[]>,
  holderPids: Set<number>
): ProcessInfo[] {
  const byPid = new Map(rows.map((row) => [row.pid, row]));
  const interesting = rows.filter(
    (row) => NAME_FILTER.test(row.command) || holderPids.has(row.pid)
  );
  return interesting.map((row) => {
    const name = processName(row.command);
    const parent = byPid.get(row.ppid);
    const heldFiles = heldByPid.get(row.pid) ?? [];
    const category = categoryFor(name, row.command);
    const inUseByModels =
      category === "simulator" && /Simulator|qemu-system|launchd_sim/i.test(name);
    const usage = evaluateProcessUsage({
      cpu: row.cpu,
      heldCleanupCount: heldFiles.filter((file) => file.role === "cleanup-target")
        .length,
      protectedProcess: category === "protected",
      inUseByModels,
      idleLeftover: category === "idle-leftover",
    });
    return {
      pid: row.pid,
      ppid: row.ppid,
      parentName: parent ? processName(parent.command) : "unknown",
      name,
      command: row.command,
      user: row.user,
      cpu: row.cpu,
      memMb: row.memMb,
      elapsed: row.elapsed,
      state: row.state,
      usage: usage.usage,
      usageReason: usage.usageReason,
      heldFiles,
      localize: {
        activityMonitor: `Activity Monitor → search ${name} or PID ${row.pid}`,
        inspect: `lsof -nP -p ${row.pid}`,
        signal: inUseByModels
          ? "Do not kill. Models are using simulators."
          : category === "protected"
            ? "Do not kill. nightshift and ai-memory stay."
            : `Confirm parent ${parent ? processName(parent.command) : "unknown"} (${row.ppid}), then kill ${row.pid}.`,
      },
      category,
      inUseByModels,
    };
  });
}

type SimctlJson = {
  devices?: Record<
    string,
    Array<{
      udid: string;
      name: string;
      state: string;
      isAvailable?: boolean;
    }>
  >;
};

async function collectSimulators(warnings: string[]): Promise<SimulatorDevice[]> {
  const { stdout, ok } = await run(
    "xcrun",
    ["simctl", "list", "devices", "--json"],
    10000
  );
  if (!ok) {
    warnings.push("simctl is unavailable. Simulator list is empty.");
    return [];
  }

  try {
    const parsed = JSON.parse(stdout) as SimctlJson;
    const devices: SimulatorDevice[] = [];
    for (const [runtimeKey, list] of Object.entries(parsed.devices ?? {})) {
      const runtime = runtimeKey
        .replace("com.apple.CoreSimulator.SimRuntime.", "")
        .replace(/-/g, " ");
      for (const device of list) {
        if (device.isAvailable === false) continue;
        const state =
          device.state === "Booted" ||
          device.state === "Shutdown" ||
          device.state === "Creating"
            ? device.state
            : "Unknown";
        const inUseByModels = state === "Booted";
        devices.push({
          udid: device.udid,
          name: device.name,
          runtime,
          state,
          inUseByModels,
          note: inUseByModels
            ? "Booted. Treated as in use by models — list only, do not close."
            : "Shutdown. Close is a no-op.",
        });
      }
    }
    devices.sort((a, b) => {
      if (a.state === b.state) return a.name.localeCompare(b.name);
      return a.state === "Booted" ? -1 : 1;
    });
    return devices;
  } catch {
    warnings.push("simctl JSON did not parse.");
    return [];
  }
}

async function collectMacSnapshot(options: {
  includeProcesses: boolean;
  reuse?: { items: CleanupItem[]; keeps: ProtectedKeep[]; host: Snapshot["host"] };
}): Promise<Snapshot> {
  const warnings: string[] = [];
  const home = homedir();
  const user = userInfo().username;

  const [osName, computer, cleanup, psOut, simulators] = await Promise.all([
    options.reuse
      ? Promise.resolve(options.reuse.host.os.replace(/^macOS\s+/, ""))
      : run("sw_vers", ["-productVersion"]).then((result) => result.stdout.trim()),
    options.reuse
      ? Promise.resolve(options.reuse.host.hostname)
      : run("scutil", ["--get", "ComputerName"]).then(
          (result) => result.stdout.trim() || hostname()
        ),
    options.reuse
      ? Promise.resolve({ items: options.reuse.items, keeps: options.reuse.keeps })
      : collectCleanup(home, warnings),
    options.includeProcesses
      ? run(
          "ps",
          ["-axo", "pid=,ppid=,user=,pcpu=,pmem=,rss=,etime=,state=,command="],
          6000
        )
      : Promise.resolve({ stdout: "", ok: true }),
    options.includeProcesses ? collectSimulators(warnings) : Promise.resolve([]),
  ]);

  const { items, keeps } = cleanup;
  let processes: ProcessInfo[] = [];
  if (options.includeProcesses) {
    if (!psOut.ok) {
      warnings.push("ps failed. Process list is empty.");
    } else {
      const rows = psOut.stdout
        .split("\n")
        .map(parsePsLine)
        .filter((row): row is NonNullable<typeof row> => row !== null);
      const holderPids = new Set(items.flatMap((item) => item.openHandles.map((handle) => handle.pid)));
      const inspectPids = rows
        .filter((row) => NAME_FILTER.test(row.command) || holderPids.has(row.pid))
        .map((row) => row.pid);
      const held = await filesForPids(
        inspectPids,
        items.map((item) => item.path)
      );
      processes = buildProcesses(rows, held, holderPids);
    }
  }

  const reclaimableBytes = items
    .filter((item) => item.usage === "idle")
    .reduce((sum, item) => sum + item.bytes, 0);
  const inUseBytes = items
    .filter((item) => item.usage === "in-use")
    .reduce((sum, item) => sum + item.bytes, 0);

  return {
    collectedAt: new Date().toISOString(),
    source: "macos",
    host: {
      hostname: computer,
      os: osName ? (osName.startsWith("macOS") ? osName : `macOS ${osName}`) : process.platform,
      user: options.reuse?.host.user ?? user,
    },
    cleanupItems: items,
    processes,
    simulators,
    protectedKeeps: keeps,
    totals: {
      reclaimableBytes,
      inUseBytes,
      protectedCount: keeps.length,
    },
    warnings,
    included: {
      cleanup: true,
      processes: options.includeProcesses,
    },
  };
}

function completeMock(): Snapshot {
  return {
    ...applySession(buildMockSnapshot()),
    included: { cleanup: true, processes: true },
  };
}

export function invalidateSnapshotCache() {
  cache = null;
}

export async function collectSnapshot(
  request: CollectRequest = {}
): Promise<Snapshot> {
  if (!isDarwin()) {
    return completeMock();
  }

  const includeProcesses = (request.tab ?? "all") !== "cleanup";

  if (!request.force && cache && Date.now() - cache.at < CACHE_TTL_MS) {
    if (!includeProcesses || cache.included.processes) {
      return applySession(cache.snapshot);
    }
  }

  if (inflight && (!includeProcesses || inflightIncludesProcesses)) {
    const current = await inflight;
    if (!includeProcesses || cache?.included.processes) {
      return current;
    }
  }

  const reuse =
    includeProcesses && cache && !cache.included.processes
      ? {
          items: cache.snapshot.cleanupItems,
          keeps: cache.snapshot.protectedKeeps,
          host: cache.snapshot.host,
        }
      : undefined;

  const runCollect = (async () => {
    try {
      const raw = await collectMacSnapshot({ includeProcesses, reuse });
      cache = {
        at: Date.now(),
        snapshot: raw,
        included: { cleanup: true, processes: includeProcesses },
      };
      return applySession(raw);
    } catch (error) {
      const fallback = completeMock();
      fallback.warnings = [
        `macOS collection failed (${error instanceof Error ? error.message : "unknown"}). Showing mock data.`,
        ...fallback.warnings,
      ];
      return fallback;
    }
  })();

  inflight = runCollect;
  inflightIncludesProcesses = includeProcesses;
  try {
    return await runCollect;
  } finally {
    if (inflight === runCollect) {
      inflight = null;
      inflightIncludesProcesses = false;
    }
  }
}
