import { UsageBadge } from "@/components/usage-badge";
import type { CleanupItem, ProcessInfo } from "@/lib/types";
import { formatRelativeTime } from "@/lib/format";

export function PathValidation({ item }: { item: CleanupItem }) {
  const handleCount = item.openHandles.length;
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-medium">Usage validation</h3>
        <UsageBadge usage={item.usage} />
      </div>
      <ol className="space-y-2 text-sm">
        <Check
          label="Open handles"
          value={
            handleCount === 0
              ? "None"
              : item.openHandles
                  .map((handle) => `${handle.process} (${handle.pid}${handle.fd ? ` fd ${handle.fd}` : ""})`)
                  .join(", ")
          }
          ok={handleCount === 0}
        />
        <Check
          label="Last access"
          value={`${formatRelativeTime(item.lastAccessAt)} · ${item.lastAccessSource}`}
          ok={item.usage === "idle"}
        />
        <Check
          label="Parent process"
          value={
            handleCount === 0
              ? "No holder — nothing to walk"
              : [...new Set(item.openHandles.map((handle) => handle.process))].join(", ")
          }
          ok={handleCount === 0}
        />
        <Check
          label="Idle vs in use"
          value={item.usageReason}
          ok={item.usage === "idle"}
        />
      </ol>
      <p className="text-sm text-muted-foreground">{item.note}</p>
    </div>
  );
}

export function ProcessValidation({ process }: { process: ProcessInfo }) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-medium">How to localize</h3>
        <UsageBadge usage={process.usage} />
      </div>
      <ol className="space-y-2 text-sm">
        <Check label="Activity Monitor" value={process.localize.activityMonitor} ok />
        <Check
          label="Parent"
          value={`${process.parentName} (ppid ${process.ppid})`}
          ok
        />
        <Check label="Open files" value={process.localize.inspect} ok />
        <Check
          label="Signal"
          value={process.localize.signal}
          ok={!process.inUseByModels && process.usage !== "protected"}
        />
      </ol>
      <p className="text-sm text-muted-foreground">{process.usageReason}</p>
    </div>
  );
}

function Check({
  label,
  value,
  ok,
}: {
  label: string;
  value: string;
  ok: boolean;
}) {
  return (
    <li className="grid grid-cols-[6.5rem_1fr] gap-3 sm:grid-cols-[8rem_1fr]">
      <span className="text-muted-foreground">{label}</span>
      <span className={ok ? "text-foreground" : "text-amber-950 dark:text-amber-200"}>
        {value}
      </span>
    </li>
  );
}
