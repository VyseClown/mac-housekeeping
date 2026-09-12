import { execFile } from "node:child_process";
import { rm } from "node:fs/promises";
import { promisify } from "node:util";

import { collectSnapshot, invalidateSnapshotCache } from "@/lib/collect";
import { buildMockSnapshot } from "@/lib/mock";
import {
  applySession,
  rememberClose,
  rememberDelete,
  rememberKill,
  sessionCanClose,
  sessionCanDelete,
  sessionCanKill,
} from "@/lib/session";
import type { ActionResult, HousekeepingAction } from "@/lib/types";

const execFileAsync = promisify(execFile);

function isDarwin(): boolean {
  if (process.env.HOUSEKEEPING_FORCE_MOCK === "1") return false;
  return process.platform === "darwin";
}

export async function performAction(
  action: HousekeepingAction
): Promise<ActionResult> {
  const snapshot = await collectSnapshot();

  if (action.type === "delete-item") {
    const gate = sessionCanDelete(snapshot, action.id);
    if (!gate.ok) return { ok: false, message: gate.message, snapshot };

    if (isDarwin()) {
      await rm(gate.item.path, { recursive: true, force: false });
    }
    rememberDelete(action.id);
    return {
      ok: true,
      message: isDarwin()
        ? `Deleted ${gate.item.path}.`
        : `Mock-deleted ${gate.item.path}. Nothing was removed on this host.`,
      snapshot: await snapshotAfterMutation(),
    };
  }

  if (action.type === "kill-process") {
    const gate = sessionCanKill(snapshot, action.pid);
    if (!gate.ok) return { ok: false, message: gate.message, snapshot };

    if (isDarwin()) {
      await execFileAsync("kill", [String(gate.process.pid)], { timeout: 4000 });
    }
    rememberKill(action.pid);
    return {
      ok: true,
      message: isDarwin()
        ? `Sent SIGTERM to ${gate.process.name} (${gate.process.pid}).`
        : `Mock-killed ${gate.process.name} (${gate.process.pid}). No signal left this host.`,
      snapshot: await snapshotAfterMutation(),
    };
  }

  const gate = sessionCanClose(snapshot, action.udid);
  if (!gate.ok) return { ok: false, message: gate.message, snapshot };

  if (isDarwin()) {
    await execFileAsync("xcrun", ["simctl", "shutdown", gate.device.udid], {
      timeout: 15000,
    });
  }
  rememberClose(action.udid);
  return {
    ok: true,
    message: isDarwin()
      ? `Requested shutdown of ${gate.device.name}.`
      : `Mock-closed ${gate.device.name}. No simulator was shut down.`,
    snapshot: await snapshotAfterMutation(),
  };
}

async function snapshotAfterMutation() {
  if (!isDarwin()) {
    return applySession(buildMockSnapshot());
  }
  invalidateSnapshotCache();
  return collectSnapshot({ force: true, tab: "all" });
}
