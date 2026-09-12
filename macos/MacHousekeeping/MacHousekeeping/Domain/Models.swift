import Foundation

enum DataSource: String, Sendable {
    case macos
    case mock
}

enum UsageState: String, Sendable {
    case inUse = "in-use"
    case idle
    case recent
    case protected
}

enum HousekeepingModule: String, CaseIterable, Identifiable, Sendable {
    case leftovers
    case media
    case worktrees
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftovers: return "Cleanup"
        case .media: return "Media"
        case .worktrees: return "Branches"
        case .processes: return "Processes"
        }
    }

    var symbol: String {
        switch self {
        case .leftovers: return "internaldrive"
        case .media: return "photo.on.rectangle.angled"
        case .worktrees: return "arrow.triangle.branch"
        case .processes: return "cpu"
        }
    }
}

struct OpenHandle: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(fd ?? "-")-\(process)" }
    var pid: Int
    var process: String
    var fd: String?
    var mode: String?
}

struct ProcessRef: Hashable, Sendable {
    var pid: Int
    var name: String
    var parentName: String
}

enum LeftoverKind: String, Sendable {
    case investigation
    case usedMedia
}

struct Leftover: Identifiable, Hashable, Sendable {
    var id: String
    var path: String
    var kind: LeftoverKind
    var bytes: Int64
    var lastAccessAt: Date
    var lastAccessSource: String
    var openHandles: [OpenHandle]
    var usage: UsageState
    var usageReason: String
    var note: String
}

enum MediaKind: String, Sendable {
    case image
    case video
}

struct MediaEvidence: Identifiable, Hashable, Sendable {
    var id: String
    var path: String
    var filename: String
    var kind: MediaKind
    var bytes: Int64
    var lastAccessAt: Date
    var lastAccessSource: String
    var usage: UsageState
    var usageReason: String
    var alreadyUsedOnPR: Bool
    var pullRequest: String?
    var holder: ProcessRef?
    var caption: String
}

enum GitWorkspaceKind: String, Sendable {
    case localBranch
    case worktree
}

enum SuggestedGitAction: Hashable, Sendable {
    case none
    case removeWorktreeLater(command: String)
    case deleteBranchLater(command: String)

    var label: String {
        switch self {
        case .none:
            return "No later cleanup suggested"
        case .removeWorktreeLater(let command):
            return command
        case .deleteBranchLater(let command):
            return command
        }
    }
}

struct GitWorkspace: Identifiable, Hashable, Sendable {
    var id: String
    var kind: GitWorkspaceKind
    var name: String
    var path: String
    var repoName: String
    var repoRoot: String
    var bytes: Int64
    var usage: UsageState
    var usageReason: String
    var holdingProcess: ProcessRef?
    var suggestedAction: SuggestedGitAction
}

enum HeldFileRole: String, Sendable {
    case cleanupTarget
    case protected
    case runtime
    case other
}

struct HeldFile: Hashable, Sendable {
    var path: String
    var role: HeldFileRole
    var bytes: Int64?
}

enum ProcessCategory: String, Sendable {
    case simulator
    case xcode
    case dev
    case idleLeftover
    case protected
}

struct MappedProcess: Identifiable, Hashable, Sendable {
    var id: Int { pid }
    var pid: Int
    var ppid: Int
    var parentName: String
    var name: String
    var command: String
    var user: String
    var cpu: Double
    var memMb: Int
    var elapsed: String
    var state: String
    var usage: UsageState
    var usageReason: String
    var heldFiles: [HeldFile]
    var localizeActivityMonitor: String
    var localizeInspect: String
    var localizeSignal: String
    var category: ProcessCategory
    var inUseByModels: Bool
}

enum SimulatorState: String, Sendable {
    case booted = "Booted"
    case shutdown = "Shutdown"
    case creating = "Creating"
    case unknown = "Unknown"
}

struct SimulatorDevice: Identifiable, Hashable, Sendable {
    var id: String { udid }
    var udid: String
    var name: String
    var runtime: String
    var state: SimulatorState
    var inUseByModels: Bool
    var note: String
}

struct ProtectedKeep: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var label: String
    var reason: String
    var present: Bool
}

struct HostInfo: Hashable, Sendable {
    var hostname: String
    var os: String
    var user: String
}

struct SpaceTotals: Hashable, Sendable {
    var leftoverBytes: Int64
    var mediaBytes: Int64
    var worktreeBytes: Int64
    var reclaimableBytes: Int64
    var inUseBytes: Int64
    var protectedCount: Int
}

struct Snapshot: Sendable {
    var collectedAt: Date
    var source: DataSource
    var host: HostInfo
    var leftovers: [Leftover]
    var media: [MediaEvidence]
    var workspaces: [GitWorkspace]
    var processes: [MappedProcess]
    var simulators: [SimulatorDevice]
    var protectedKeeps: [ProtectedKeep]
    var totals: SpaceTotals
    var warnings: [String]
}

enum DestructiveIntent: Identifiable, Hashable, Sendable {
    case deleteLeftover(id: String)
    case killProcess(pid: Int)

    var id: String {
        switch self {
        case .deleteLeftover(let id): return "delete-\(id)"
        case .killProcess(let pid): return "kill-\(pid)"
        }
    }
}

enum LoadState: Sendable {
    case idle
    case loading
    case ready(Snapshot)
    case failed(String)
}
