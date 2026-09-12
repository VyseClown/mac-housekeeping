import { daysSince } from "@/lib/format";
import type { OpenHandle, UsageState } from "@/lib/types";

export function evaluatePathUsage(input: {
  openHandles: OpenHandle[];
  lastAccessAt: string;
  protectedPath: boolean;
}): { usage: UsageState; usageReason: string } {
  if (input.protectedPath) {
    return {
      usage: "protected",
      usageReason: "Matches nightshift or ai-memory. Kept; never flagged.",
    };
  }

  if (input.openHandles.length > 0) {
    const holders = uniqueNames(input.openHandles);
    return {
      usage: "in-use",
      usageReason: `Open handle${input.openHandles.length === 1 ? "" : "s"} from ${holders}.`,
    };
  }

  const age = daysSince(input.lastAccessAt);
  if (age < 2) {
    return {
      usage: "recent",
      usageReason:
        "No open handles, but last access is under two days. Review before delete.",
    };
  }

  return {
    usage: "idle",
    usageReason: `No open handles. Last access ${Math.round(age)} days ago. Looks unused.`,
  };
}

export function evaluateProcessUsage(input: {
  cpu: number;
  heldCleanupCount: number;
  protectedProcess: boolean;
  inUseByModels: boolean;
  idleLeftover: boolean;
}): { usage: UsageState; usageReason: string } {
  if (input.protectedProcess) {
    return {
      usage: "protected",
      usageReason: "nightshift or ai-memory process. Do not kill.",
    };
  }
  if (input.inUseByModels) {
    return {
      usage: "in-use",
      usageReason: "Models are using this process. Leave it running.",
    };
  }
  if (input.heldCleanupCount > 0 && input.cpu > 0.5) {
    return {
      usage: "in-use",
      usageReason: "Holding leftover files and consuming CPU.",
    };
  }
  if (input.idleLeftover && input.cpu < 0.3) {
    return {
      usage: "idle",
      usageReason: "Orphaned leftover with near-zero CPU. Candidate to localize and kill.",
    };
  }
  if (input.cpu < 0.2 && input.heldCleanupCount === 0) {
    return {
      usage: "recent",
      usageReason: "Quiet, but not classified as a leftover. Inspect parent and files first.",
    };
  }
  return {
    usage: "in-use",
    usageReason: "Active developer process. Do not treat as leftover.",
  };
}

function uniqueNames(handles: OpenHandle[]): string {
  return [...new Set(handles.map((h) => h.process))].join(", ");
}
