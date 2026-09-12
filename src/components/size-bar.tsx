import { formatBytes } from "@/lib/format";
import { cn } from "@/lib/utils";

export function SizeBar({
  bytes,
  maxBytes,
  className,
}: {
  bytes: number;
  maxBytes: number;
  className?: string;
}) {
  const ratio = maxBytes > 0 ? Math.max(0.04, Math.min(1, bytes / maxBytes)) : 0;
  return (
    <div className={cn("flex min-w-28 flex-col gap-1", className)}>
      <div className="flex items-baseline justify-between gap-2">
        <span className="font-mono text-xs tabular-nums">{formatBytes(bytes)}</span>
      </div>
      <div className="h-1 overflow-hidden rounded-full bg-muted">
        <div
          className="h-full rounded-full bg-primary/70"
          style={{ width: `${ratio * 100}%` }}
        />
      </div>
    </div>
  );
}
