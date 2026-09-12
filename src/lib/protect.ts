const PROTECTED_RE = /nightshift|ai[-_]?memory/i;

export function isProtectedPath(path: string): boolean {
  return PROTECTED_RE.test(path);
}

export function isProtectedProcess(name: string, command: string): boolean {
  return isProtectedPath(name) || isProtectedPath(command);
}

export const DEFAULT_PROTECTED_KEEPS = [
  {
    path: "/Users/alessandro/nightshift",
    label: "nightshift",
    reason: "Installed on purpose. Never a cleanup candidate.",
  },
  {
    path: "/Users/alessandro/ai-memory",
    label: "ai-memory",
    reason: "Installed on purpose. Never a cleanup candidate.",
  },
] as const;
