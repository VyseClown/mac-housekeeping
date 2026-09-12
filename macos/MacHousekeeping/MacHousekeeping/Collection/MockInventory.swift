import Foundation

enum MockInventory {
    static let mediaBytes: Int64 = 30_064_771_072
    static let worktreeBytes: Int64 = 24_696_061_952

    static func daysAgo(_ days: Double) -> Date {
        Date().addingTimeInterval(-days * 86_400)
    }

    static func hoursAgo(_ hours: Double) -> Date {
        Date().addingTimeInterval(-hours * 3_600)
    }

    static func snapshot() -> Snapshot {
        let leftovers = Protection.rejecting(leftoverItems(), path: \.path)
        let media = Protection.rejecting(mediaItems(), path: \.path)
        let workspaces = Protection.rejecting(workspaceItems(), path: \.path)
        let processes = processItems()
        let keeps = Protection.keeps(home: "/Users/alessandro")

        precondition(!leftovers.contains { Protection.blocks($0.path) })
        precondition(!media.contains { Protection.blocks($0.path) })
        precondition(!workspaces.contains { Protection.blocks($0.path) })

        let mediaSum = media.reduce(Int64(0)) { $0 + $1.bytes }
        let worktreeSum = workspaces
            .filter { $0.kind == .worktree }
            .reduce(Int64(0)) { $0 + $1.bytes }
        precondition(mediaSum == mediaBytes)
        precondition(worktreeSum == worktreeBytes)

        let leftoverBytes = leftovers.reduce(Int64(0)) { $0 + $1.bytes }
        let reclaimable =
            leftovers.filter { $0.usage == .idle }.reduce(Int64(0)) { $0 + $1.bytes }
            + media.filter { $0.usage == .idle }.reduce(Int64(0)) { $0 + $1.bytes }
            + workspaces.filter { $0.usage == .idle }.reduce(Int64(0)) { $0 + $1.bytes }
        let inUse =
            leftovers.filter { $0.usage == .inUse }.reduce(Int64(0)) { $0 + $1.bytes }
            + media.filter { $0.usage == .inUse }.reduce(Int64(0)) { $0 + $1.bytes }
            + workspaces.filter { $0.usage == .inUse }.reduce(Int64(0)) { $0 + $1.bytes }

        return Snapshot(
            collectedAt: Date(),
            source: .mock,
            host: HostInfo(
                hostname: "Alessandros-MacBook-Pro.local",
                os: "macOS 15.6.1 (mock — this host is not Darwin)",
                user: "alessandro"
            ),
            leftovers: leftovers,
            media: media,
            workspaces: workspaces,
            processes: processes,
            simulators: simulatorItems(),
            protectedKeeps: keeps,
            totals: SpaceTotals(
                leftoverBytes: leftoverBytes,
                mediaBytes: mediaSum,
                worktreeBytes: worktreeSum,
                reclaimableBytes: reclaimable,
                inUseBytes: inUse,
                protectedCount: keeps.count
            ),
            warnings: [
                "Running off-Mac. Snapshot is a stand-in for Alessandro's machine so the UI can be reviewed here.",
            ]
        )
    }

    private static func leftoverItems() -> [Leftover] {
        [
            Leftover(
                id: "inv-trace",
                path: "/Users/alessandro/Downloads/investigation-2026-03-trace",
                kind: .investigation,
                bytes: 1_524_658_176,
                lastAccessAt: daysAgo(12),
                lastAccessSource: "mock",
                openHandles: [],
                usage: .idle,
                usageReason: "No open handles. Last access 12 days ago. Looks unused.",
                note: "Packet and log dump from the March crash hunt. Work is finished."
            ),
            Leftover(
                id: "inv-har",
                path: "/Users/alessandro/Desktop/repro-har-dumps",
                kind: .investigation,
                bytes: 195_035_136,
                lastAccessAt: daysAgo(8),
                lastAccessSource: "mock",
                openHandles: [],
                usage: .idle,
                usageReason: "No open handles. Last access 8 days ago. Looks unused.",
                note: "HAR files from a network repro. Already attached to the ticket."
            ),
            Leftover(
                id: "inv-derived",
                path: "/Users/alessandro/Library/Developer/Xcode/DerivedData/investigation-scratch-gkxw",
                kind: .investigation,
                bytes: 933_232_640,
                lastAccessAt: daysAgo(15),
                lastAccessSource: "mock",
                openHandles: [],
                usage: .idle,
                usageReason: "No open handles. Last access 15 days ago. Looks unused.",
                note: "DerivedData for a throwaway investigation Xcode target."
            ),
            Leftover(
                id: "inv-pcap",
                path: "/tmp/investigation-packet-captures",
                kind: .investigation,
                bytes: 75_497_472,
                lastAccessAt: daysAgo(4),
                lastAccessSource: "mock",
                openHandles: [
                    OpenHandle(pid: 33901, process: "tcpdump", fd: "3", mode: "w"),
                ],
                usage: .inUse,
                usageReason: "Open handles from tcpdump.",
                note: "Still held by a leftover tcpdump from the same investigation."
            ),
        ]
    }

    private static func mediaItems() -> [MediaEvidence] {
        [
            MediaEvidence(
                id: "prove-login",
                path: "/Users/alessandro/Desktop/pr-evidence/prove-login-flow.mov",
                filename: "prove-login-flow.mov",
                kind: .video,
                bytes: 8_912_568_320,
                lastAccessAt: daysAgo(11),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 11 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1842",
                holder: nil,
                caption: "Login walkthrough already attached to the PR."
            ),
            MediaEvidence(
                id: "evidence-repro",
                path: "/Users/alessandro/Desktop/pr-evidence/evidence-repro-loop.mp4",
                filename: "evidence-repro-loop.mp4",
                kind: .video,
                bytes: 6_442_188_800,
                lastAccessAt: daysAgo(9),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 9 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1838",
                holder: nil,
                caption: "Repro loop already used as PR evidence."
            ),
            MediaEvidence(
                id: "pr-walkthrough",
                path: "/Users/alessandro/Desktop/pr-evidence/pr-1842-walkthrough.mov",
                filename: "pr-1842-walkthrough.mov",
                kind: .video,
                bytes: 5_368_709_120,
                lastAccessAt: daysAgo(11),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 11 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1842",
                holder: nil,
                caption: "Desktop walkthrough already posted on the PR."
            ),
            MediaEvidence(
                id: "prove-settings",
                path: "/Users/alessandro/Desktop/pr-evidence/prove-settings-pass.mov",
                filename: "prove-settings-pass.mov",
                kind: .video,
                bytes: 5_235_081_216,
                lastAccessAt: daysAgo(6),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 6 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1851",
                holder: nil,
                caption: "Settings pass already used to prove the review."
            ),
            MediaEvidence(
                id: "prove-network",
                path: "/Users/alessandro/Desktop/pr-evidence/prove-network-fail.mp4",
                filename: "prove-network-fail.mp4",
                kind: .video,
                bytes: 3_489_660_928,
                lastAccessAt: daysAgo(14),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 14 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1820",
                holder: nil,
                caption: "Network failure clip already attached."
            ),
            MediaEvidence(
                id: "crash-01",
                path: "/Users/alessandro/Desktop/investigation-screens/crash-01.png",
                filename: "crash-01.png",
                kind: .image,
                bytes: 184_549_376,
                lastAccessAt: daysAgo(16),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 16 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1811",
                holder: nil,
                caption: "Crash still already used on the investigation PR."
            ),
            MediaEvidence(
                id: "crash-02",
                path: "/Users/alessandro/Desktop/investigation-screens/crash-02.png",
                filename: "crash-02.png",
                kind: .image,
                bytes: 201_326_592,
                lastAccessAt: hoursAgo(6),
                lastAccessSource: "mock",
                usage: .inUse,
                usageReason: "Open handles from Preview.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1811",
                holder: ProcessRef(pid: 77812, name: "Preview", parentName: "launchd"),
                caption: "Screenshot still open in Preview."
            ),
            MediaEvidence(
                id: "before-settings",
                path: "/Users/alessandro/Desktop/investigation-screens/before-settings.png",
                filename: "before-settings.png",
                kind: .image,
                bytes: 92_274_688,
                lastAccessAt: daysAgo(7),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 7 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1851",
                holder: nil,
                caption: "Before still already compared on the PR."
            ),
            MediaEvidence(
                id: "ui-pass-01",
                path: "/Users/alessandro/Desktop/pr-evidence/used-exports/ui-pass-01.png",
                filename: "ui-pass-01.png",
                kind: .image,
                bytes: 48_234_496,
                lastAccessAt: daysAgo(18),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 18 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1794",
                holder: nil,
                caption: "Used export already shipped."
            ),
            MediaEvidence(
                id: "ui-pass-02",
                path: "/Users/alessandro/Desktop/pr-evidence/used-exports/ui-pass-02.png",
                filename: "ui-pass-02.png",
                kind: .image,
                bytes: 51_380_224,
                lastAccessAt: daysAgo(18),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 18 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1794",
                holder: nil,
                caption: "Used export already shipped."
            ),
            MediaEvidence(
                id: "session-still",
                path: "/Users/alessandro/Desktop/pr-evidence/session-14-review-still.png",
                filename: "session-14-review-still.png",
                kind: .image,
                bytes: 38_797_312,
                lastAccessAt: daysAgo(21),
                lastAccessSource: "mock",
                usage: .idle,
                usageReason: "No open handles. Last access 21 days ago. Looks unused.",
                alreadyUsedOnPR: true,
                pullRequest: "PR #1770",
                holder: nil,
                caption: "Review still already pulled into the write-up."
            ),
        ]
    }

    private static func workspaceItems() -> [GitWorkspace] {
        [
            GitWorkspace(
                id: "wt-housekeeping",
                kind: .worktree,
                name: "cursor/mac-housekeeping-app-6d19",
                path: "/tmp/cursor-worktree-housekeeping-a1",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 8_794_800_128,
                usage: .idle,
                usageReason: "No process holds this worktree. Last git activity is stale.",
                holdingProcess: nil,
                suggestedAction: .removeWorktreeLater(
                    command: "git worktree remove /tmp/cursor-worktree-housekeeping-a1"
                )
            ),
            GitWorkspace(
                id: "wt-agent",
                kind: .worktree,
                name: "cursor/agent-scratch-b2",
                path: "/tmp/cursor-worktree-agent-b2",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 7_623_176_192,
                usage: .inUse,
                usageReason: "Cursor still has this worktree open.",
                holdingProcess: ProcessRef(pid: 9102, name: "Cursor", parentName: "launchd"),
                suggestedAction: .removeWorktreeLater(
                    command: "git worktree remove /tmp/cursor-worktree-agent-b2"
                )
            ),
            GitWorkspace(
                id: "wt-review",
                kind: .worktree,
                name: "cursor/pr-review-c3",
                path: "/tmp/cursor-worktree-pr-review-c3",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 5_798_764_544,
                usage: .idle,
                usageReason: "No process holds this worktree. Review already merged.",
                holdingProcess: nil,
                suggestedAction: .removeWorktreeLater(
                    command: "git worktree remove /tmp/cursor-worktree-pr-review-c3"
                )
            ),
            GitWorkspace(
                id: "wt-old",
                kind: .worktree,
                name: "cursor/old-spike-d4",
                path: "/tmp/cursor-worktree-old-d4",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 2_479_321_088,
                usage: .idle,
                usageReason: "No process holds this worktree. Branch is abandoned.",
                holdingProcess: nil,
                suggestedAction: .removeWorktreeLater(
                    command: "git worktree remove /tmp/cursor-worktree-old-d4"
                )
            ),
            GitWorkspace(
                id: "br-main",
                kind: .localBranch,
                name: "main",
                path: "/Users/alessandro/src/mac-housekeeping",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 0,
                usage: .inUse,
                usageReason: "Primary checkout. Objects already counted on disk at the repo root.",
                holdingProcess: ProcessRef(pid: 9102, name: "Cursor", parentName: "launchd"),
                suggestedAction: .none
            ),
            GitWorkspace(
                id: "br-housekeeping",
                kind: .localBranch,
                name: "cursor/mac-housekeeping-app-6d19",
                path: "/Users/alessandro/src/mac-housekeeping",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 0,
                usage: .recent,
                usageReason: "Local branch also checked out in a /tmp worktree.",
                holdingProcess: nil,
                suggestedAction: .deleteBranchLater(
                    command: "git branch -d cursor/mac-housekeeping-app-6d19"
                )
            ),
            GitWorkspace(
                id: "br-old",
                kind: .localBranch,
                name: "cursor/old-spike-d4",
                path: "/Users/alessandro/src/mac-housekeeping",
                repoName: "mac-housekeeping",
                repoRoot: "/Users/alessandro/src/mac-housekeeping",
                bytes: 0,
                usage: .idle,
                usageReason: "Local branch for an abandoned /tmp worktree.",
                holdingProcess: nil,
                suggestedAction: .deleteBranchLater(
                    command: "git branch -d cursor/old-spike-d4"
                )
            ),
        ]
    }

    private static func processItems() -> [MappedProcess] {
        [
            MappedProcess(
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
                usage: .inUse,
                usageReason: "Models are using this process. Leave it running.",
                heldFiles: [
                    HeldFile(
                        path: "/Users/alessandro/Library/Developer/CoreSimulator/Devices/A1B2C3D4-1111-2222-3333-444455556666/data",
                        role: .runtime,
                        bytes: nil
                    ),
                ],
                localizeActivityMonitor: "Activity Monitor → search Simulator or PID 18421",
                localizeInspect: "lsof -nP -p 18421",
                localizeSignal: "Do not kill. If you later close this device, use simctl shutdown. Never now. Models are using it.",
                category: .simulator,
                inUseByModels: true
            ),
            MappedProcess(
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
                usage: .inUse,
                usageReason: "Models are using this process. Leave it running.",
                heldFiles: [
                    HeldFile(
                        path: "/Users/alessandro/Library/Developer/CoreSimulator/Devices/B2C3D4E5-7777-8888-9999-000011112222/data",
                        role: .runtime,
                        bytes: nil
                    ),
                ],
                localizeActivityMonitor: "Activity Monitor → search Simulator or PID 18488",
                localizeInspect: "lsof -nP -p 18488",
                localizeSignal: "Do not kill. Models are using the iPad simulator.",
                category: .simulator,
                inUseByModels: true
            ),
            MappedProcess(
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
                usage: .inUse,
                usageReason: "Active developer process. Do not treat as leftover.",
                heldFiles: [
                    HeldFile(
                        path: "/Users/alessandro/Library/Developer/Xcode/DerivedData",
                        role: .runtime,
                        bytes: nil
                    ),
                ],
                localizeActivityMonitor: "Activity Monitor → search Xcode or PID 12011",
                localizeInspect: "lsof -nP -p 12011 | head",
                localizeSignal: "Quit from Xcode. kill 12011 only if it is wedged.",
                category: .xcode,
                inUseByModels: false
            ),
            MappedProcess(
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
                usage: .inUse,
                usageReason: "Active developer process. Do not treat as leftover.",
                heldFiles: [
                    HeldFile(path: "/Users/alessandro/ai-memory", role: .protected, bytes: nil),
                    HeldFile(path: "/tmp/cursor-worktree-agent-b2", role: .runtime, bytes: 7_623_176_192),
                ],
                localizeActivityMonitor: "Activity Monitor → search Cursor or PID 9102",
                localizeInspect: "lsof -nP -p 9102",
                localizeSignal: "Quit from Cursor. Holding ai-memory. Not a kill target.",
                category: .dev,
                inUseByModels: false
            ),
            MappedProcess(
                pid: 55210,
                ppid: 1,
                parentName: "launchd",
                name: "ffmpeg",
                command: "ffmpeg -i prove-login-flow.mov -c copy /tmp/prove-login-transcode.mp4",
                user: "alessandro",
                cpu: 0.0,
                memMb: 18,
                elapsed: "4-03:22:01",
                state: "T",
                usage: .idle,
                usageReason: "Orphaned leftover with near-zero CPU. Candidate to localize and kill.",
                heldFiles: [
                    HeldFile(
                        path: "/Users/alessandro/Desktop/pr-evidence/prove-login-flow.mov",
                        role: .cleanupTarget,
                        bytes: 8_912_568_320
                    ),
                ],
                localizeActivityMonitor: "Activity Monitor → search ffmpeg or PID 55210",
                localizeInspect: "lsof -nP -p 55210",
                localizeSignal: "Stopped leftover encode. Confirm parent launchd, then kill 55210.",
                category: .idleLeftover,
                inUseByModels: false
            ),
            MappedProcess(
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
                usage: .idle,
                usageReason: "Orphaned leftover with near-zero CPU. Candidate to localize and kill.",
                heldFiles: [
                    HeldFile(
                        path: "/tmp/investigation-packet-captures",
                        role: .cleanupTarget,
                        bytes: 75_497_472
                    ),
                ],
                localizeActivityMonitor: "Activity Monitor → search tcpdump or PID 33901",
                localizeInspect: "lsof -nP -p 33901",
                localizeSignal: "Parent is launchd. Orphaned capture. sudo kill 33901 after you confirm the pcap is done.",
                category: .idleLeftover,
                inUseByModels: false
            ),
            MappedProcess(
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
                usage: .inUse,
                usageReason: "Holding leftover files and consuming CPU.",
                heldFiles: [
                    HeldFile(
                        path: "/Users/alessandro/Desktop/investigation-screens/crash-02.png",
                        role: .cleanupTarget,
                        bytes: 201_326_592
                    ),
                ],
                localizeActivityMonitor: "Activity Monitor → search Preview or PID 77812",
                localizeInspect: "lsof -nP -p 77812",
                localizeSignal: "Quit Preview to release the screenshot, then re-validate before delete.",
                category: .dev,
                inUseByModels: false
            ),
        ]
    }

    private static func simulatorItems() -> [SimulatorDevice] {
        [
            SimulatorDevice(
                udid: "A1B2C3D4-1111-2222-3333-444455556666",
                name: "iPhone 16 Pro",
                runtime: "iOS 18.5",
                state: .booted,
                inUseByModels: true,
                note: "Models are using this device. List only. Do not close."
            ),
            SimulatorDevice(
                udid: "B2C3D4E5-7777-8888-9999-000011112222",
                name: "iPad Pro 13-inch (M4)",
                runtime: "iOS 18.5",
                state: .booted,
                inUseByModels: true,
                note: "Models are using this device. List only. Do not close."
            ),
            SimulatorDevice(
                udid: "C3D4E5F6-AAAA-BBBB-CCCC-DDDDEEEEFFFF",
                name: "iPhone SE (3rd generation)",
                runtime: "iOS 18.5",
                state: .shutdown,
                inUseByModels: false,
                note: "Already off. Close is a no-op."
            ),
            SimulatorDevice(
                udid: "D4E5F6A7-1212-3434-5656-787890901212",
                name: "iPhone 15",
                runtime: "iOS 17.5",
                state: .shutdown,
                inUseByModels: false,
                note: "Already off. Close is a no-op."
            ),
        ]
    }
}
