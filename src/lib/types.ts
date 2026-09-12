export type DataSource = "macos" | "mock";

export type UsageState = "in-use" | "idle" | "recent" | "protected";

export type CleanupKind = "investigation-leftover" | "used-media";

export type OpenHandle = {
  pid: number;
  process: string;
  fd: string | null;
  mode: string | null;
};

export type CleanupItem = {
  id: string;
  path: string;
  kind: CleanupKind;
  bytes: number;
  lastAccessAt: string;
  lastAccessSource: "stat" | "mock";
  openHandles: OpenHandle[];
  usage: UsageState;
  usageReason: string;
  note: string;
};

export type HeldFile = {
  path: string;
  role: "cleanup-target" | "protected" | "runtime" | "other";
  bytes: number | null;
};

export type ProcessCategory =
  | "simulator"
  | "xcode"
  | "dev"
  | "idle-leftover"
  | "protected";

export type ProcessInfo = {
  pid: number;
  ppid: number;
  parentName: string;
  name: string;
  command: string;
  user: string;
  cpu: number;
  memMb: number;
  elapsed: string;
  state: string;
  usage: UsageState;
  usageReason: string;
  heldFiles: HeldFile[];
  localize: {
    activityMonitor: string;
    inspect: string;
    signal: string;
  };
  category: ProcessCategory;
  inUseByModels: boolean;
};

export type SimulatorDevice = {
  udid: string;
  name: string;
  runtime: string;
  state: "Booted" | "Shutdown" | "Creating" | "Unknown";
  inUseByModels: boolean;
  note: string;
};

export type ProtectedKeep = {
  path: string;
  label: string;
  reason: string;
  present: boolean;
};

export type Snapshot = {
  collectedAt: string;
  source: DataSource;
  host: {
    hostname: string;
    os: string;
    user: string;
  };
  cleanupItems: CleanupItem[];
  processes: ProcessInfo[];
  simulators: SimulatorDevice[];
  protectedKeeps: ProtectedKeep[];
  totals: {
    reclaimableBytes: number;
    inUseBytes: number;
    protectedCount: number;
  };
  warnings: string[];
  included?: {
    cleanup: boolean;
    processes: boolean;
  };
};

export type HousekeepingAction =
  | { type: "delete-item"; id: string }
  | { type: "kill-process"; pid: number }
  | { type: "close-simulator"; udid: string };

export type ActionResult = {
  ok: boolean;
  message: string;
  snapshot: Snapshot;
};
