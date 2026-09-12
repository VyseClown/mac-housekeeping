import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { UsageState } from "@/lib/types";

const LABEL: Record<UsageState, string> = {
  idle: "Idle",
  "in-use": "In use",
  recent: "Recent",
  protected: "Kept",
};

export function UsageBadge({
  usage,
  className,
}: {
  usage: UsageState;
  className?: string;
}) {
  return (
    <Badge
      variant="outline"
      className={cn(
        "rounded-md border font-medium",
        usage === "idle" &&
          "border-emerald-700/20 bg-emerald-700/8 text-emerald-900 dark:text-emerald-300",
        usage === "in-use" &&
          "border-amber-800/20 bg-amber-800/8 text-amber-950 dark:text-amber-200",
        usage === "recent" &&
          "border-stone-400/40 bg-stone-400/10 text-stone-700 dark:text-stone-300",
        usage === "protected" &&
          "border-sky-800/20 bg-sky-800/8 text-sky-950 dark:text-sky-200",
        className
      )}
    >
      {LABEL[usage]}
    </Badge>
  );
}
