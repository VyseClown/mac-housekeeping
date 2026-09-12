const UNITS = ["B", "KB", "MB", "GB", "TB"] as const;

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return "—";
  if (bytes === 0) return "0 B";
  const exp = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    UNITS.length - 1
  );
  const value = bytes / 1024 ** exp;
  const digits = value >= 100 || exp === 0 ? 0 : value >= 10 ? 1 : 2;
  return `${value.toFixed(digits)} ${UNITS[exp]}`;
}

export function formatRelativeTime(
  iso: string,
  now: Date = new Date()
): string {
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return "unknown";
  const deltaMs = now.getTime() - then.getTime();
  const abs = Math.abs(deltaMs);
  const minutes = Math.round(abs / 60_000);
  const hours = Math.round(abs / 3_600_000);
  const days = Math.round(abs / 86_400_000);
  const suffix = deltaMs >= 0 ? "ago" : "from now";
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ${suffix}`;
  if (hours < 36) return `${hours}h ${suffix}`;
  if (days < 60) return `${days}d ${suffix}`;
  return then.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function daysSince(iso: string, now: Date = new Date()): number {
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return Number.POSITIVE_INFINITY;
  return (now.getTime() - then.getTime()) / 86_400_000;
}
