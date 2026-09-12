import { DEFAULT_PROTECTED_KEEPS } from "@/lib/protect";
import type {
  CleanupItem,
  ProcessInfo,
  ProtectedKeep,
  SimulatorDevice,
  Snapshot,
} from "@/lib/types";

function daysAgo(days: number): string {
  return new Date(Date.now() - days * 86_400_000).toISOString();
}

function hoursAgo(hours: number): string {
  return new Date(Date.now() - hours * 3_600_000).toISOString();
}

const CLEANUP_ITEMS: CleanupItem[] = [
  {
    id: "inv-trace",
    path: "/Users/alessandro/Downloads/investigation-2026-03-trace",
    kind: "investigation-leftover",
    bytes: 1_524_658_176,
    lastAccessAt: daysAgo(12),
    lastAccessSource: "mock",
    openHandles: [],
    usage: "idle",
    usageReason: "No open handles. Last access 12 days ago. Looks unused.",
    note: "Packet and log dump from the March crash hunt. Work is finished.",
  },
  {
    id: "inv-har",
    path: "/Users/alessandro/Desktop/repro-har-dumps",
    kind: "investigation-leftover",
    bytes: 195_035_136,
    lastAccessAt: daysAgo(8),
    lastAccessSource: "mock",
    openHandles: [],
    usage: "idle",
    usageReason: "No open handles. Last access 8 days ago. Looks unused.",
    note: "HAR files from a network repro. Already attached to the ticket.",
  },
  {
    id: "inv-derived",
    path: "/Users/alessandro/Library/Developer/Xcode/DerivedData/investigation-scratch-gkxw",
    kind: "investigation-leftover",
    bytes: 933_232_640,
    lastAccessAt: daysAgo(15),
    lastAccessSource: "mock",
    openHandles: [],
    usage: "idle",
    usageReason: "No open handles. Last access 15 days ago. Looks unused.",
    note: "DerivedData for a throwaway investigation Xcode target.",
  },
  {
    id: "inv-pcap",
    path: "/tmp/investigation-packet-captures",
    kind: "investigation-leftover",
    bytes: 75_497_472,
    lastAccessAt: daysAgo(4),
    lastAccessSource: "mock",
    openHandles: [
      {
        pid: 33901,
        process: "tcpdump",
        fd: "3",
        mode: "w",
      },
    ],
    usage: "in-use",
    usageReason: "Open handles from tcpdump.",
    note: "Still held by a leftover tcpdump from the same investigation.",
  },
  {
    id: "inv-screens",
    path: "/Users/alessandro/Desktop/investigation-screens",
    kind: "investigation-leftover",
    bytes: 43_018_240,
    lastAccessAt: hoursAgo(6),
    lastAccessSource: "mock",
    openHandles: [
      {
        pid: 77812,
        process: "Preview",
        fd: "8",
        mode: "r",
      },
    ],
    usage: "in-use",
    usageReason: "Open handles from Preview.",
    note: "Screenshot set still open in Preview.",
  },
  {
    id: "used-mov",
    path: "/Users/alessandro/Movies/used-captures/session-14-review.mov",
    kind: "used-media",
    bytes: 2_340_782_080,
    lastAccessAt: daysAgo(21),
    lastAccessSource: "mock",
    openHandles: [],
    usage: "idle",
    usageReason: "No open handles. Last access 21 days ago. Looks unused.",
    note: "Review capture already pulled into the write-up.",
  },
  {
    id: "used-exports",
    path: "/Users/alessandro/Pictures/used-exports/ui-pass",
    kind: "used-media",
    bytes: 98_566_144,
    lastAccessAt: daysAgo(18),
    lastAccessSource: "mock",
    openHandles: [],
    usage: "idle",
    usageReason: "No open handles. Last access 18 days ago. Looks unused.",
    note: "PNG exports already shipped. Folder name marks them used.",
  },
  {
    id: "used-review",
    path: "/Users/alessandro/Downloads/used-review-batch",
    kind: "used-media",
    bytes: 356_515_840,
    lastAccessAt: daysAgo(9),
    lastAccessSource: "mock",
    openHandles: [],
    usage: "idle",
    usageReason: "No open handles. Last access 9 days ago. Looks unused.",
    note: "Mixed images and short clips from a finished review pass.",
  },
];

const PROCESSES: ProcessInfo[] = [
  {
    pid: 18421,
    ppid: 1,
    parentName: "launchd",
    name: "Simulator",
    command: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator",
    user: "alessandro",
    cpu: 2.4,
    memMb: 612,
    elapsed: "04:12:09",
    state: "S",
    usage: "in-use",
    usageReason: "Models are using this process. Leave it running.",
    heldFiles: [
      {
        path: "/Users/alessandro/Library/Developer/CoreSimulator/Devices/A1B2C3D4-1111-2222-3333-444455556666/data",
        role: "runtime",
        bytes: null,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search Simulator or PID 18421",
      inspect: "lsof -nP -p 18421",
      signal: "Do not kill. If you later close this device, use simctl shutdown — never now; models are using it.",
    },
    category: "simulator",
    inUseByModels: true,
  },
  {
    pid: 18488,
    ppid: 1,
    parentName: "launchd",
    name: "Simulator",
    command: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator",
    user: "alessandro",
    cpu: 1.1,
    memMb: 488,
    elapsed: "04:12:02",
    state: "S",
    usage: "in-use",
    usageReason: "Models are using this process. Leave it running.",
    heldFiles: [
      {
        path: "/Users/alessandro/Library/Developer/CoreSimulator/Devices/B2C3D4E5-7777-8888-9999-000011112222/data",
        role: "runtime",
        bytes: null,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search Simulator or PID 18488",
      inspect: "lsof -nP -p 18488",
      signal: "Do not kill. Models are using the iPad simulator.",
    },
    category: "simulator",
    inUseByModels: true,
  },
  {
    pid: 12011,
    ppid: 1,
    parentName: "launchd",
    name: "Xcode",
    command: "/Applications/Xcode.app/Contents/MacOS/Xcode",
    user: "alessandro",
    cpu: 3.8,
    memMb: 1420,
    elapsed: "1-02:18:44",
    state: "S",
    usage: "in-use",
    usageReason: "Active developer process. Do not treat as leftover.",
    heldFiles: [
      {
        path: "/Users/alessandro/Library/Developer/Xcode/DerivedData",
        role: "runtime",
        bytes: null,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search Xcode or PID 12011",
      inspect: "lsof -nP -p 12011 | head",
      signal: "Quit from Xcode. kill 12011 only if it is wedged.",
    },
    category: "xcode",
    inUseByModels: false,
  },
  {
    pid: 44102,
    ppid: 9102,
    parentName: "Cursor",
    name: "node",
    command: "next-server (mac-housekeeping)",
    user: "alessandro",
    cpu: 0.6,
    memMb: 214,
    elapsed: "00:41:12",
    state: "S",
    usage: "in-use",
    usageReason: "Active developer process. Do not treat as leftover.",
    heldFiles: [],
    localize: {
      activityMonitor: "Activity Monitor → search node or PID 44102",
      inspect: "lsof -nP -p 44102",
      signal: "This is the housekeeping app. Do not kill it from here.",
    },
    category: "dev",
    inUseByModels: false,
  },
  {
    pid: 9102,
    ppid: 1,
    parentName: "launchd",
    name: "Cursor",
    command: "/Applications/Cursor.app/Contents/MacOS/Cursor",
    user: "alessandro",
    cpu: 4.2,
    memMb: 980,
    elapsed: "1-06:02:11",
    state: "S",
    usage: "in-use",
    usageReason: "Active developer process. Do not treat as leftover.",
    heldFiles: [
      {
        path: "/Users/alessandro/ai-memory",
        role: "protected",
        bytes: null,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search Cursor or PID 9102",
      inspect: "lsof -nP -p 9102",
      signal: "Quit from Cursor. Holding ai-memory — not a kill target.",
    },
    category: "dev",
    inUseByModels: false,
  },
  {
    pid: 55210,
    ppid: 1,
    parentName: "launchd",
    name: "ffmpeg",
    command: "ffmpeg -i session-14-review.mov -c copy /tmp/session-14-transcode.mp4",
    user: "alessandro",
    cpu: 0.0,
    memMb: 18,
    elapsed: "4-03:22:01",
    state: "T",
    usage: "idle",
    usageReason: "Orphaned leftover with near-zero CPU. Candidate to localize and kill.",
    heldFiles: [
      {
        path: "/Users/alessandro/Movies/used-captures/session-14-review.mov",
        role: "cleanup-target",
        bytes: 2_340_782_080,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search ffmpeg or PID 55210",
      inspect: "lsof -nP -p 55210",
      signal: "Stopped leftover encode. Confirm parent launchd, then kill 55210.",
    },
    category: "idle-leftover",
    inUseByModels: false,
  },
  {
    pid: 33901,
    ppid: 1,
    parentName: "launchd",
    name: "tcpdump",
    command: "tcpdump -i any -w /tmp/investigation-packet-captures/en0.pcap",
    user: "root",
    cpu: 0.0,
    memMb: 9,
    elapsed: "4-11:08:33",
    state: "S",
    usage: "idle",
    usageReason: "Orphaned leftover with near-zero CPU. Candidate to localize and kill.",
    heldFiles: [
      {
        path: "/tmp/investigation-packet-captures",
        role: "cleanup-target",
        bytes: 75_497_472,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search tcpdump or PID 33901",
      inspect: "lsof -nP -p 33901",
      signal: "Parent is launchd — orphaned capture. sudo kill 33901 after you confirm the pcap is done.",
    },
    category: "idle-leftover",
    inUseByModels: false,
  },
  {
    pid: 77812,
    ppid: 1,
    parentName: "launchd",
    name: "Preview",
    command: "/System/Applications/Preview.app/Contents/MacOS/Preview",
    user: "alessandro",
    cpu: 0.1,
    memMb: 64,
    elapsed: "00:18:44",
    state: "S",
    usage: "in-use",
    usageReason: "Holding leftover files and consuming CPU.",
    heldFiles: [
      {
        path: "/Users/alessandro/Desktop/investigation-screens",
        role: "cleanup-target",
        bytes: 43_018_240,
      },
    ],
    localize: {
      activityMonitor: "Activity Monitor → search Preview or PID 77812",
      inspect: "lsof -nP -p 77812",
      signal: "Quit Preview to release the screenshot folder, then re-validate before delete.",
    },
    category: "dev",
    inUseByModels: false,
  },
];

const SIMULATORS: SimulatorDevice[] = [
  {
    udid: "A1B2C3D4-1111-2222-3333-444455556666",
    name: "iPhone 16 Pro",
    runtime: "iOS 18.5",
    state: "Booted",
    inUseByModels: true,
    note: "Models are using this device. List only — do not close.",
  },
  {
    udid: "B2C3D4E5-7777-8888-9999-000011112222",
    name: "iPad Pro 13-inch (M4)",
    runtime: "iOS 18.5",
    state: "Booted",
    inUseByModels: true,
    note: "Models are using this device. List only — do not close.",
  },
  {
    udid: "C3D4E5F6-AAAA-BBBB-CCCC-DDDDEEEEFFFF",
    name: "iPhone SE (3rd generation)",
    runtime: "iOS 18.5",
    state: "Shutdown",
    inUseByModels: false,
    note: "Already off. Close is a no-op.",
  },
  {
    udid: "D4E5F6A7-1212-3434-5656-787890901212",
    name: "iPhone 15",
    runtime: "iOS 17.5",
    state: "Shutdown",
    inUseByModels: false,
    note: "Already off. Close is a no-op.",
  },
];

function protectedKeeps(): ProtectedKeep[] {
  return DEFAULT_PROTECTED_KEEPS.map((keep) => ({
    ...keep,
    present: true,
  }));
}

export function buildMockSnapshot(): Snapshot {
  const cleanupItems = CLEANUP_ITEMS.map((item) => ({ ...item }));
  const reclaimableBytes = cleanupItems
    .filter((item) => item.usage === "idle")
    .reduce((sum, item) => sum + item.bytes, 0);
  const inUseBytes = cleanupItems
    .filter((item) => item.usage === "in-use")
    .reduce((sum, item) => sum + item.bytes, 0);

  return {
    collectedAt: new Date().toISOString(),
    source: "mock",
    host: {
      hostname: "Alessandros-MacBook-Pro.local",
      os: "macOS 15.6.1 (mock — this host is not Darwin)",
      user: "alessandro",
    },
    cleanupItems,
    processes: PROCESSES.map((process) => ({
      ...process,
      heldFiles: process.heldFiles.map((file) => ({ ...file })),
    })),
    simulators: SIMULATORS.map((device) => ({ ...device })),
    protectedKeeps: protectedKeeps(),
    totals: {
      reclaimableBytes,
      inUseBytes,
      protectedCount: DEFAULT_PROTECTED_KEEPS.length,
    },
    warnings: [
      "Running off-Mac. Snapshot is a realistic stand-in for Alessandro's machine so the UI can be used here.",
    ],
  };
}

export function mockCleanupItems(): CleanupItem[] {
  return CLEANUP_ITEMS.map((item) => ({ ...item }));
}

export function mockProcesses(): ProcessInfo[] {
  return PROCESSES.map((process) => ({
    ...process,
    heldFiles: process.heldFiles.map((file) => ({ ...file })),
  }));
}

export function mockSimulators(): SimulatorDevice[] {
  return SIMULATORS.map((device) => ({ ...device }));
}
