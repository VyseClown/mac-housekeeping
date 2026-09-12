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

const NAME_FILTER =
  /Simulator|launchd_sim|qemu-system|CoreSimulator|Xcode|SourceKit|node|Cursor|ffmpeg|tcpdump|Preview|nightshift|ai-memory|ai_memory/i;

const CANDIDATE_MATCH =
  /investigation|repro-har|repro-screen|used-capture|used-export|used-review|already-used/i;

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

async function handlesFor(path: string): Promise<OpenHandle[]> {
  const { stdout, ok } = await run("lsof", ["-nP", "--", path], 6000);
  if (!ok || !stdout.trim()) return [];
  const handles: OpenHandle[] = [];
  for (const line of stdout.split("\n").slice(1)) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 4) continue;
    const process = parts[0];
    const pid = Number.parseInt(parts[1] ?? "", 10);
    if (!Number.isFinite(pid)) continue;
    handles.push({
      pid,
      process,
      fd: parts[3] ?? null,
      mode: parts[4] ?? null,
    });
  }
  return handles;
}

async function findCandidates(home: string): Promise<string[]> {
  const roots = [
    `${home}/Downloads`,
    `${home}/Desktop`,
    `${home}/Documents`,
    `${home}/Movies`,
    `${home}/Pictures`,
    `${home}/Library/Developer/Xcode/DerivedData`,
    "/tmp",
  ].filter((root) => existsSync(root));

  if (roots.length === 0) return [];

  const { stdout } = await run(
    "find",
    [
      ...roots,
      "-maxdepth",
      "4",
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

  const seen = new Set<string>();
  const paths: string[] = [];
  for (const line of stdout.split("\n")) {
    const path = line.trim();
    if (!path || seen.has(path)) continue;
    if (!CANDIDATE_MATCH.test(path)) continue;
    seen.add(path);
    paths.push(path);
  }
  return paths;
}

async function collectCleanup(
  home: string,
  warnings: string[]
): Promise<{ items: CleanupItem[]; keeps: ProtectedKeep[] }> {
  const found = await findCandidates(home);
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

  const items: CleanupItem[] = [];
  for (const path of found) {
    if (isProtectedPath(path)) continue;
    const [bytes, lastAccessAt, openHandles] = await Promise.all([
      pathBytes(path),
      lastAccessIso(path),
      handlesFor(path),
    ]);
    const kind = kindFor(path);
    const usage = evaluatePathUsage({
      openHandles,
      lastAccessAt,
      protectedPath: false,
    });
    items.push({
      id: slug(path),
      path,
      kind,
      bytes,
      lastAccessAt,
      lastAccessSource: "stat",
      openHandles,
      usage: usage.usage,
      usageReason: usage.usageReason,
      note: noteFor(path, kind),
    });
  }

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

async function filesForPid(
  pid: number,
  cleanupPaths: string[]
): Promise<HeldFile[]> {
  const { stdout, ok } = await run("lsof", ["-nP", "-p", String(pid)], 5000);
  if (!ok) return [];
  const held: HeldFile[] = [];
  const seen = new Set<string>();
  for (const line of stdout.split("\n").slice(1)) {
    const pathMatch = line.match(/(\/[\w./ -]+)$/);
    const path = pathMatch?.[1]?.trim();
    if (!path || seen.has(path)) continue;
    if (
      !CANDIDATE_MATCH.test(path) &&
      !isProtectedPath(path) &&
      !/CoreSimulator|DerivedData/i.test(path)
    ) {
      continue;
    }
    seen.add(path);
    const role: HeldFile["role"] = isProtectedPath(path)
      ? "protected"
      : cleanupPaths.some((candidate) => path.startsWith(candidate) || candidate.startsWith(path))
        ? "cleanup-target"
        : /CoreSimulator|DerivedData/i.test(path)
          ? "runtime"
          : "other";
    held.push({ path, role, bytes: null });
    if (held.length >= 6) break;
  }
  return held;
}

async function collectProcesses(
  cleanupItems: CleanupItem[],
  warnings: string[]
): Promise<ProcessInfo[]> {
  const { stdout, ok } = await run(
    "ps",
    ["-axo", "pid=,ppid=,user=,pcpu=,pmem=,rss=,etime=,state=,command="],
    6000
  );
  if (!ok) {
    warnings.push("ps failed. Process list is empty.");
    return [];
  }

  const rows = stdout
    .split("\n")
    .map(parsePsLine)
    .filter((row): row is NonNullable<typeof row> => row !== null);

  const byPid = new Map(rows.map((row) => [row.pid, row]));
  const interesting = rows.filter((row) =>
    NAME_FILTER.test(row.command)
  );

  const cleanupPaths = cleanupItems.map((item) => item.path);
  const processes: ProcessInfo[] = [];

  for (const row of interesting) {
    const name = processName(row.command);
    const parent = byPid.get(row.ppid);
    const heldFiles = await filesForPid(row.pid, cleanupPaths);
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

    processes.push({
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
    });
  }

  return processes;
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
      const runtime = runtimeKey.replace("com.apple.CoreSimulator.SimRuntime.", "").replace(/-/g, " ");
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

async function collectMacSnapshot(): Promise<Snapshot> {
  const warnings: string[] = [];
  const home = homedir();
  const user = userInfo().username;
  const osName = (await run("sw_vers", ["-productVersion"])).stdout.trim();
  const computer =
    (await run("scutil", ["--get", "ComputerName"])).stdout.trim() || hostname();

  const { items, keeps } = await collectCleanup(home, warnings);
  const processes = await collectProcesses(items, warnings);
  const simulators = await collectSimulators(warnings);

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
      os: osName ? `macOS ${osName}` : process.platform,
      user,
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
  };
}

export async function collectSnapshot(): Promise<Snapshot> {
  if (!isDarwin()) {
    return applySession(buildMockSnapshot());
  }
  try {
    return applySession(await collectMacSnapshot());
  } catch (error) {
    const fallback = applySession(buildMockSnapshot());
    fallback.warnings = [
      `macOS collection failed (${error instanceof Error ? error.message : "unknown"}). Showing mock data.`,
      ...fallback.warnings,
    ];
    return fallback;
  }
}
