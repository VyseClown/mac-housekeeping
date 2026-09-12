import { buildMockSnapshot } from "@/lib/mock";
import { isProtectedPath, isProtectedProcess } from "@/lib/protect";
import type { Snapshot } from "@/lib/types";

const deletedItemIds = new Set<string>();
const killedPids = new Set<number>();
const closedUdids = new Set<string>();

export function applySession(snapshot: Snapshot): Snapshot {
  const cleanupItems = snapshot.cleanupItems.filter(
    (item) => !deletedItemIds.has(item.id)
  );
  const processes = snapshot.processes.filter(
    (process) => !killedPids.has(process.pid)
  );
  const simulators = snapshot.simulators.map((device) =>
    closedUdids.has(device.udid)
      ? {
          ...device,
          state: "Shutdown" as const,
          note: "Closed in this session after an explicit request.",
        }
      : device
  );

  const reclaimableBytes = cleanupItems
    .filter((item) => item.usage === "idle")
    .reduce((sum, item) => sum + item.bytes, 0);
  const inUseBytes = cleanupItems
    .filter((item) => item.usage === "in-use")
    .reduce((sum, item) => sum + item.bytes, 0);

  return {
    ...snapshot,
    cleanupItems,
    processes,
    simulators,
    totals: {
      ...snapshot.totals,
      reclaimableBytes,
      inUseBytes,
    },
  };
}

export function rememberDelete(id: string) {
  deletedItemIds.add(id);
}

export function rememberKill(pid: number) {
  killedPids.add(pid);
}

export function rememberClose(udid: string) {
  closedUdids.add(udid);
}

export function sessionCanDelete(snapshot: Snapshot, id: string) {
  const item = snapshot.cleanupItems.find((entry) => entry.id === id);
  if (!item) return { ok: false as const, message: "Item is not in the current snapshot." };
  if (isProtectedPath(item.path) || item.usage === "protected") {
    return { ok: false as const, message: "nightshift and ai-memory are never deleted." };
  }
  if (item.openHandles.length > 0 || item.usage === "in-use") {
    return {
      ok: false as const,
      message: "Still has open handles. Release the process, then re-validate.",
    };
  }
  return { ok: true as const, item };
}

export function sessionCanKill(snapshot: Snapshot, pid: number) {
  const process = snapshot.processes.find((entry) => entry.pid === pid);
  if (!process) return { ok: false as const, message: "Process is not in the current snapshot." };
  if (
    isProtectedProcess(process.name, process.command) ||
    process.usage === "protected" ||
    process.category === "protected"
  ) {
    return { ok: false as const, message: "nightshift and ai-memory processes are never killed." };
  }
  if (process.inUseByModels) {
    return { ok: false as const, message: "Models are using this process. Leave it running." };
  }
  return { ok: true as const, process };
}

export function sessionCanClose(snapshot: Snapshot, udid: string) {
  const device = snapshot.simulators.find((entry) => entry.udid === udid);
  if (!device) return { ok: false as const, message: "Simulator is not in the current list." };
  if (device.inUseByModels) {
    return {
      ok: false as const,
      message: "Models are using this simulator. Close stays disabled.",
    };
  }
  if (device.state !== "Booted") {
    return { ok: false as const, message: `${device.name} is already ${device.state.toLowerCase()}.` };
  }
  return { ok: true as const, device };
}

export function emptyMockAfterSession(): Snapshot {
  return applySession(buildMockSnapshot());
}
