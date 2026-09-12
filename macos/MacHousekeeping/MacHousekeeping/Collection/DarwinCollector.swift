import Foundation

enum DarwinCollector {
    static let leftoverNameGlobs = [
        "*investigation*", "*repro*", "*already-used*",
        "*evidence*", "*prove*", "*artifacts*",
        "*pr-*", "PR-*", "*recording*", "*demo-live*",
    ]
    static let mediaVideoLimit = 48
    static let mediaImageLimit = 24

    static func leftoverNamePattern() -> String {
        "investigation|repro|already-used|evidence|prove|artifacts|pr-|recording|demo-live|sbs|walkthrough|overlay"
    }

    static func looksLikeLeftoverName(_ name: String) -> Bool {
        name.range(
            of: leftoverNamePattern(),
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func repoSearchRoots(home: String) -> [String] {
        [
            "\(home)/work",
            "\(home)/src",
            "\(home)/Developer",
            "\(home)/Projects",
            "\(home)/code",
        ]
    }

    static func isDesktopMediaCandidate(depth: Int, bytes: Int64, video: Bool, image: Bool) -> Bool {
        if video && depth <= 5 { return true }
        if (video || image) && depth == 1 { return true }
        if image && depth <= 5 && bytes > 400 * 1024 { return true }
        return false
    }

    static func uniqueExistingPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let resolved = (path as NSString).resolvingSymlinksInPath
            if seen.contains(resolved) { continue }
            seen.insert(resolved)
            result.append(path)
        }
        return result
    }

    static func isDarwin() -> Bool {
        if ProcessInfo.processInfo.environment["HOUSEKEEPING_FORCE_MOCK"] == "1" {
            return false
        }
        if ProcessInfo.processInfo.environment["HOUSEKEEPING_FORCE_MAC"] == "1" {
            return true
        }
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    static func collect() throws -> Snapshot {
        var warnings: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let user = NSUserName()
        let hostname = run("scutil", ["--get", "ComputerName"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let osVersion = run("sw_vers", ["-productVersion"]).trimmingCharacters(in: .whitespacesAndNewlines)

        let desktop = "\(home)/Desktop"
        let desktopWalk = walkDesktop(desktop)
        let workspaces = collectWorkspaces(home: home, warnings: &warnings)
        let worktreePaths = Set(workspaces.filter { $0.kind == .worktree }.map(\.path))
        let leftovers = collectLeftovers(
            home: home,
            desktopWalk: desktopWalk,
            excluding: worktreePaths,
            warnings: &warnings
        )
        let media = collectMedia(desktopWalk: desktopWalk, warnings: &warnings)
        let processes = collectProcesses(cleanupPaths: leftovers.map(\.path) + media.map(\.path), warnings: &warnings)
        let simulators = collectSimulators(warnings: &warnings)
        let keeps = Protection.keeps(home: home).map { keep in
            var copy = keep
            copy.present = FileManager.default.fileExists(atPath: keep.path)
            return copy
        }

        let leftoverBytes = leftovers.reduce(Int64(0)) { $0 + $1.bytes }
        let mediaBytes = media.reduce(Int64(0)) { $0 + $1.bytes }
        let worktreeBytes = workspaces.filter { $0.kind == .worktree }.reduce(Int64(0)) { $0 + $1.bytes }
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
            source: .macos,
            host: HostInfo(
                hostname: hostname.isEmpty ? ProcessInfo.processInfo.hostName : hostname,
                os: osVersion.isEmpty ? "macOS" : "macOS \(osVersion)",
                user: user
            ),
            leftovers: leftovers,
            media: media,
            workspaces: workspaces,
            processes: processes,
            simulators: simulators,
            protectedKeeps: keeps,
            totals: SpaceTotals(
                leftoverBytes: leftoverBytes,
                mediaBytes: mediaBytes,
                worktreeBytes: worktreeBytes,
                reclaimableBytes: reclaimable,
                inUseBytes: inUse,
                protectedCount: keeps.count
            ),
            warnings: warnings
        )
    }

    private static func collectLeftovers(
        home: String,
        desktopWalk: DesktopInventory,
        excluding worktreePaths: Set<String>,
        warnings: inout [String]
    ) -> [Leftover] {
        var paths = Set(desktopWalk.topLevelDirectories)
        let roots = uniqueExistingPaths([
            "\(home)/Downloads",
            "\(home)/Documents",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "/tmp",
            "/private/tmp",
        ])

        if !roots.isEmpty {
            var args = roots + ["-maxdepth", "3", "("]
            for (index, name) in leftoverNameGlobs.enumerated() {
                if index > 0 { args.append("-o") }
                args.append(contentsOf: ["-iname", name])
            }
            args.append(")")
            for path in run("find", args + ["-type", "d"], timeoutSeconds: 25)
                .split(separator: "\n").map(String.init)
            {
                guard !path.isEmpty else { continue }
                paths.insert(path)
            }
        }

        let resolvedWorktrees = Set(worktreePaths.flatMap { [$0, ($0 as NSString).resolvingSymlinksInPath] })
        let found = paths
            .filter { path in
                !Protection.blocks(path)
                    && !isMediaPath(path)
                    && !resolvedWorktrees.contains(path)
                    && !resolvedWorktrees.contains((path as NSString).resolvingSymlinksInPath)
            }
            .sorted()

        if found.isEmpty {
            warnings.append("No leftover folders matched on this Mac.")
        }

        let desktopRoot = desktopWalk.root
        let desktopPrefix = desktopRoot.hasSuffix("/") ? desktopRoot : desktopRoot + "/"
        return found.map { path in
            let handles = handlesFor(path)
            let access = lastAccess(path)
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false
            )
            let onDesktop = path == desktopRoot || path.hasPrefix(desktopPrefix)
            let bytes: Int64
            if onDesktop {
                bytes = desktopWalk.directoryBytes[path]
                    ?? desktopWalk.directoryBytes[(path as NSString).resolvingSymlinksInPath]
                    ?? 0
            } else {
                bytes = pathBytes(path)
            }
            return Leftover(
                id: slug(path),
                path: path,
                kind: .investigation,
                bytes: bytes,
                lastAccessAt: access,
                lastAccessSource: "stat",
                openHandles: handles,
                usage: usage.0,
                usageReason: usage.1,
                note: "Leftover folder. Eligible only after usage validates idle."
            )
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func collectMedia(desktopWalk: DesktopInventory, warnings: inout [String]) -> [MediaEvidence] {
        let candidates = desktopWalk.media.filter { !Protection.blocks($0.path) }
        let rankedVideos = candidates
            .filter(\.video)
            .sorted { lhs, rhs in
                if lhs.loose != rhs.loose { return lhs.loose }
                return lhs.bytes > rhs.bytes
            }
        let rankedImages = candidates
            .filter { !$0.video }
            .sorted { lhs, rhs in
                if lhs.loose != rhs.loose { return lhs.loose }
                return lhs.bytes > rhs.bytes
            }

        let picked = Array(rankedVideos.prefix(mediaVideoLimit)) + Array(rankedImages.prefix(mediaImageLimit))
        if picked.isEmpty {
            warnings.append("No Desktop prove or evidence media matched on this Mac. Grant Desktop access if the folder is on this Mac.")
        } else if candidates.count > picked.count {
            warnings.append(
                "Showing the largest \(picked.count) Desktop leftover images and videos of \(candidates.count) scanned."
            )
        }

        return picked.map { hit in
            let handles = hit.video && hit.loose ? handlesFor(hit.path) : []
            let access = hit.accessed
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false
            )
            let filename = (hit.path as NSString).lastPathComponent
            let holder = handles.first.map {
                ProcessRef(pid: $0.pid, name: $0.process, parentName: "unknown")
            }
            return MediaEvidence(
                id: slug(hit.path),
                path: hit.path,
                filename: filename,
                kind: hit.video ? .video : .image,
                bytes: hit.bytes,
                lastAccessAt: access,
                lastAccessSource: "stat",
                usage: usage.0,
                usageReason: usage.1,
                alreadyUsedOnPR: true,
                pullRequest: inferredPR(hit.path),
                holder: holder,
                caption: "Already-used Desktop evidence. Eligible only after usage validates idle."
            )
        }
    }

    private static func collectWorkspaces(home: String, warnings: inout [String]) -> [GitWorkspace] {
        let repoRoots = discoverRepos(home: home)
        if repoRoots.isEmpty {
            warnings.append("No git repositories found under the home project folders.")
        }

        var workspaces: [GitWorkspace] = []
        var seenPaths = Set<String>()
        var seenGitDirs = Set<String>()

        for repo in repoRoots {
            if Protection.blocks(repo) { continue }
            let gitEntry = (repo as NSString).appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitEntry) else { continue }
            if let gitdir = resolvedGitDir(repo) {
                if seenGitDirs.contains(gitdir) { continue }
                seenGitDirs.insert(gitdir)
            }

            let porcelain = run("git", ["-C", repo, "worktree", "list", "--porcelain"])
            appendWorktrees(
                from: porcelain,
                repo: repo,
                seenPaths: &seenPaths,
                into: &workspaces
            )

            let branches = run("git", ["-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/heads"])
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
            for branch in branches {
                if Protection.blocks(branch) { continue }
                let id = slug("\(repo)-\(branch)")
                if workspaces.contains(where: { $0.id == id }) { continue }
                workspaces.append(
                    GitWorkspace(
                        id: id,
                        kind: .localBranch,
                        name: branch,
                        path: repo,
                        repoName: (repo as NSString).lastPathComponent,
                        repoRoot: repo,
                        bytes: 0,
                        usage: .recent,
                        usageReason: "Local branch. Unique objects live in the repo. Not a worktree checkout.",
                        holdingProcess: nil,
                        suggestedAction: .deleteBranchLater(command: "git branch -d \(branch)")
                    )
                )
            }
        }

        for orphan in tmpWorktreeOrphans(excluding: seenPaths) {
            if let gitdir = resolvedGitDir(orphan) {
                if seenGitDirs.contains(gitdir) { continue }
                seenGitDirs.insert(gitdir)
            }
            let porcelain = run("git", ["-C", orphan, "worktree", "list", "--porcelain"])
            if porcelain.isEmpty {
                appendLeftoverWorktree(path: orphan, repo: orphan, branch: (orphan as NSString).lastPathComponent, seenPaths: &seenPaths, into: &workspaces)
            } else {
                appendWorktrees(from: porcelain, repo: orphan, seenPaths: &seenPaths, into: &workspaces)
            }
        }

        return workspaces.sorted { $0.bytes > $1.bytes }
    }

    private static func collectProcesses(cleanupPaths: [String], warnings: inout [String]) -> [MappedProcess] {
        let output = run("ps", ["-axo", "pid=,ppid=,user=,pcpu=,pmem=,rss=,etime=,state=,command="])
        if output.isEmpty {
            warnings.append("ps failed. Process list is empty.")
            return []
        }

        let filter = try? NSRegularExpression(
            pattern: "Simulator|launchd_sim|qemu-system|CoreSimulator|Xcode|SourceKit|node|Cursor|ffmpeg|tcpdump|Preview|QuickTime|QTKit|VLC|nightshift|night-shift|ai-memory|ai_memory"
        )
        var rows: [(pid: Int, ppid: Int, user: String, cpu: Double, memMb: Int, elapsed: String, state: String, command: String)] = []
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count >= 9,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let cpu = Double(parts[3]),
                  let rss = Int(parts[5])
            else { continue }
            rows.append((
                pid: pid,
                ppid: ppid,
                user: String(parts[2]),
                cpu: cpu,
                memMb: rss / 1024,
                elapsed: String(parts[6]),
                state: String(parts[7]),
                command: String(parts[8])
            ))
        }

        let byPid = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        return rows.compactMap { row in
            let command = row.command
            let range = NSRange(command.startIndex..., in: command)
            guard filter?.firstMatch(in: command, range: range) != nil else { return nil }
            let name = ((command.split(separator: " ").first.map(String.init) ?? command) as NSString).lastPathComponent
            if Protection.blocksProcess(name: name, command: command) {
                return nil
            }
            let parent = byPid[row.ppid]
            let parentName = parent.map { (($0.command.split(separator: " ").first.map(String.init) ?? $0.command) as NSString).lastPathComponent } ?? "unknown"
            let shouldInspect =
                command.contains("/tmp")
                || command.contains("/Desktop")
                || command.contains("investigation")
                || name.range(of: "QuickTime|QTKit|Preview|ffmpeg|qemu", options: .regularExpression) != nil
            let held = shouldInspect ? filesForPid(row.pid, cleanupPaths: cleanupPaths) : []
            let category = categoryFor(name: name, command: command)
            let inUseByModels = category == .simulator
            let usage = UsageEvaluator.processUsage(
                cpu: row.cpu,
                heldCleanupCount: held.filter { $0.role == .cleanupTarget }.count,
                protectedProcess: false,
                inUseByModels: inUseByModels,
                idleLeftover: category == .idleLeftover
            )
            return MappedProcess(
                pid: row.pid,
                ppid: row.ppid,
                parentName: parentName,
                name: name,
                command: command,
                user: row.user,
                cpu: row.cpu,
                memMb: row.memMb,
                elapsed: row.elapsed,
                state: row.state,
                usage: usage.0,
                usageReason: usage.1,
                heldFiles: held,
                localizeActivityMonitor: "Activity Monitor → search \(name) or PID \(row.pid)",
                localizeInspect: "lsof -nP -p \(row.pid)",
                localizeSignal: inUseByModels
                    ? "Do not kill. Models are using simulators."
                    : "Confirm parent \(parentName) (\(row.ppid)), then kill \(row.pid).",
                category: category,
                inUseByModels: inUseByModels
            )
        }
    }

    private static func collectSimulators(warnings: inout [String]) -> [SimulatorDevice] {
        let json = run("xcrun", ["simctl", "list", "devices", "--json"])
        guard !json.isEmpty, let data = json.data(using: .utf8) else {
            warnings.append("simctl is unavailable. Simulator list is empty.")
            return []
        }
        guard
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = parsed["devices"] as? [String: [[String: Any]]]
        else {
            warnings.append("simctl JSON did not parse.")
            return []
        }

        var result: [SimulatorDevice] = []
        for (runtimeKey, list) in devices {
            let runtime = runtimeKey
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            for device in list {
                if let available = device["isAvailable"] as? Bool, available == false { continue }
                guard let udid = device["udid"] as? String, let name = device["name"] as? String else { continue }
                let raw = device["state"] as? String ?? "Unknown"
                let state: SimulatorState
                switch raw {
                case "Booted": state = .booted
                case "Shutdown": state = .shutdown
                case "Creating": state = .creating
                default: state = .unknown
                }
                let inUse = state == .booted
                result.append(
                    SimulatorDevice(
                        udid: udid,
                        name: name,
                        runtime: runtime,
                        state: state,
                        inUseByModels: inUse,
                        note: inUse
                            ? "Booted. Treated as in use by models. List only, do not close."
                            : "Shutdown. Close is a no-op."
                    )
                )
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.state == rhs.state { return lhs.name < rhs.name }
            return lhs.state == .booted
        }
    }

    private static func discoverRepos(home: String) -> [String] {
        let roots = uniqueExistingPaths(repoSearchRoots(home: home))
        guard !roots.isEmpty else { return [] }
        let output = run("find", roots + ["-maxdepth", "5", "-name", ".git"])
        var repos: [String] = []
        for line in output.split(separator: "\n") {
            let gitPath = String(line)
            let repo = gitPath.hasSuffix("/.git")
                ? String(gitPath.dropLast(5))
                : gitPath
            if !Protection.blocks(repo) {
                repos.append(repo)
            }
        }
        return Array(Set(repos)).sorted()
    }

    private static func tmpWorktreeOrphans(excluding seen: Set<String>) -> [String] {
        var orphans: [String] = []
        for root in uniqueExistingPaths(["/tmp", "/private/tmp"]) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in names {
                let path = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let git = (path as NSString).appendingPathComponent(".git")
                guard FileManager.default.fileExists(atPath: git) else { continue }
                if Protection.blocks(path) { continue }
                let resolved = (path as NSString).resolvingSymlinksInPath
                if seen.contains(path) || seen.contains(resolved) { continue }
                orphans.append(path)
            }
        }
        return orphans
    }

    private static func appendWorktrees(
        from porcelain: String,
        repo: String,
        seenPaths: inout Set<String>,
        into workspaces: inout [GitWorkspace]
    ) {
        let blocks = porcelain.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n").map(String.init)
            guard let worktreeLine = lines.first(where: { $0.hasPrefix("worktree ") }) else { continue }
            let path = String(worktreeLine.dropFirst("worktree ".count))
            let branch = lines.first(where: { $0.hasPrefix("branch ") })
                .map { String($0.dropFirst("branch ".count)).replacingOccurrences(of: "refs/heads/", with: "") }
                ?? (lines.contains(where: { $0 == "bare" }) ? "(bare)" : "detached")
            appendLeftoverWorktree(path: path, repo: repo, branch: branch, seenPaths: &seenPaths, into: &workspaces)
        }
    }

    private static func appendLeftoverWorktree(
        path: String,
        repo: String,
        branch: String,
        seenPaths: inout Set<String>,
        into workspaces: inout [GitWorkspace]
    ) {
        let resolved = (path as NSString).resolvingSymlinksInPath
        if seenPaths.contains(path) || seenPaths.contains(resolved) || Protection.blocks(path) { return }
        seenPaths.insert(path)
        seenPaths.insert(resolved)
        let leftoverTree = path.contains("/tmp/") || path.contains("/private/tmp/")
        let handles = leftoverTree ? handlesFor(path) : []
        let holder = handles.first.map {
            ProcessRef(pid: $0.pid, name: $0.process, parentName: "unknown")
        }
        let usage = UsageEvaluator.pathUsage(
            openHandles: handles,
            lastAccessAt: leftoverTree ? lastAccess(path) : Date(),
            protectedPath: false
        )
        workspaces.append(
            GitWorkspace(
                id: slug(path),
                kind: .worktree,
                name: branch,
                path: path,
                repoName: (repo as NSString).lastPathComponent,
                repoRoot: repo,
                bytes: leftoverTree ? pathBytes(path) : 0,
                usage: usage.0,
                usageReason: leftoverTree
                    ? usage.1
                    : "Active checkout. Listed for review; size is left on the leftover /tmp slice.",
                holdingProcess: holder,
                suggestedAction: leftoverTree
                    ? .removeWorktreeLater(command: "git worktree remove \(path)")
                    : .none
            )
        )
    }

    private static func resolvedGitDir(_ repo: String) -> String? {
        let git = (repo as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            return (git as NSString).resolvingSymlinksInPath
        }
        guard let text = try? String(contentsOfFile: git, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("gitdir:") {
                let raw = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                return (raw as NSString).resolvingSymlinksInPath
            }
        }
        return nil
    }

    private static func filesForPid(_ pid: Int, cleanupPaths: [String]) -> [HeldFile] {
        let output = run("lsof", ["-nP", "-p", String(pid)], timeoutSeconds: 6)
        var held: [HeldFile] = []
        var seen = Set<String>()
        for line in output.split(separator: "\n").dropFirst() {
            guard let path = line.split(separator: " ").map(String.init).last, path.hasPrefix("/") else { continue }
            if seen.contains(path) { continue }
            let interesting = looksLikeEvidence(path)
                || path.contains("investigation")
                || path.contains("CoreSimulator")
                || path.contains("DerivedData")
                || path.contains("worktree")
                || Protection.blocks(path)
            if !interesting { continue }
            seen.insert(path)
            let role: HeldFileRole
            if Protection.blocks(path) {
                role = .protected
            } else if cleanupPaths.contains(where: { path.hasPrefix($0) || $0.hasPrefix(path) }) {
                role = .cleanupTarget
            } else if path.contains("CoreSimulator") || path.contains("DerivedData") || path.contains("worktree") {
                role = .runtime
            } else {
                role = .other
            }
            held.append(HeldFile(path: path, role: role, bytes: nil))
            if held.count >= 6 { break }
        }
        return held
    }

    private static func categoryFor(name: String, command: String) -> ProcessCategory {
        let blob = name + command
        if blob.range(of: "Simulator|launchd_sim|qemu-system|CoreSimulator", options: .regularExpression) != nil {
            return .simulator
        }
        if blob.range(of: "Xcode|SourceKit", options: .regularExpression) != nil {
            return .xcode
        }
        if blob.range(of: "ffmpeg|tcpdump", options: .regularExpression) != nil {
            return .idleLeftover
        }
        return .dev
    }

    private static func looksLikeEvidence(_ path: String) -> Bool {
        path.range(
            of: leftoverNamePattern() + "|used-capture|used-export|used-review|pr-evidence|prove-|evidence-",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isMediaPath(_ path: String) -> Bool {
        isVideo(path) || isImage(path)
    }

    private static func isImage(_ path: String) -> Bool {
        path.range(of: "\\.(png|jpe?g|heic|webp)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isVideo(_ path: String) -> Bool {
        path.range(of: "\\.(mov|mp4|m4v)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func inferredPR(_ path: String) -> String? {
        if let match = path.range(of: "pr-(\\d+)", options: .regularExpression) {
            let digits = path[match].split(separator: "-").last.map(String.init) ?? ""
            return digits.isEmpty ? nil : "PR #\(digits)"
        }
        if let match = path.range(of: "\\d{3,5}", options: .regularExpression) {
            return "Ticket \(path[match])"
        }
        return nil
    }

    private static func handlesFor(_ path: String) -> [OpenHandle] {
        let output = run("lsof", ["-nP", "--", path], timeoutSeconds: 6)
        var handles: [OpenHandle] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, let pid = Int(parts[1]) else { continue }
            handles.append(OpenHandle(pid: pid, process: parts[0], fd: parts[3], mode: parts.count > 4 ? parts[4] : nil))
        }
        return handles
    }

    private static func walkDesktop(_ desktop: String) -> DesktopInventory {
        var inventory = DesktopInventory(root: desktop, topLevelDirectories: [], directoryBytes: [:], media: [])
        guard FileManager.default.fileExists(atPath: desktop) else { return inventory }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentAccessDateKey,
        ]
        let rootURL = URL(fileURLWithPath: desktop, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return inventory }

        let prefix = desktop.hasSuffix("/") ? desktop : desktop + "/"
        while let url = enumerator.nextObject() as? URL {
            let path = url.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }
            let depth = relative.split(separator: "/").count
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory == true
            let isLink = values?.isSymbolicLink == true

            if isDir && depth == 1 {
                inventory.topLevelDirectories.append(path)
            }
            if isDir && isLink {
                enumerator.skipDescendants()
                continue
            }
            if isDir { continue }

            let bytes = Int64(values?.fileSize ?? 0)
            if let top = relative.split(separator: "/").first {
                let topPath = prefix + String(top)
                inventory.directoryBytes[topPath, default: 0] += bytes
            }

            let video = isVideo(path)
            let image = isImage(path)
            if isDesktopMediaCandidate(depth: depth, bytes: bytes, video: video, image: image) {
                inventory.media.append(
                    DesktopMediaHit(
                        path: path,
                        bytes: bytes,
                        video: video,
                        loose: depth == 1,
                        accessed: values?.contentAccessDate ?? Date(timeIntervalSince1970: 0)
                    )
                )
            }
        }
        return inventory
    }

    private static func pathBytes(_ path: String) -> Int64 {
        let output = run("du", ["-sk", path], timeoutSeconds: 90)
        let kb = Int64(output.split(separator: "\t").first ?? output.split(separator: " ").first ?? "0") ?? 0
        return kb * 1024
    }

    private static func lastAccess(_ path: String) -> Date {
        let mac = run("stat", ["-f", "%a", path]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(mac) { return Date(timeIntervalSince1970: seconds) }
        return Date(timeIntervalSince1970: 0)
    }

    private static func slug(_ path: String) -> String {
        let raw = path.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return String(raw.trimmingCharacters(in: CharacterSet(charactersIn: "-")).suffix(48))
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String], timeoutSeconds: Double = 30) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launchPath] + arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let buffer = NSMutableData()
        let lock = NSLock()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            lock.lock()
            buffer.append(chunk)
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            return ""
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeoutSeconds) == .timedOut, process.isRunning {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        let tail = stdout.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        buffer.append(tail)
        let data = Data(referencing: buffer)
        lock.unlock()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct DesktopInventory {
    var root: String
    var topLevelDirectories: [String]
    var directoryBytes: [String: Int64]
    var media: [DesktopMediaHit]
}

private struct DesktopMediaHit {
    var path: String
    var bytes: Int64
    var video: Bool
    var loose: Bool
    var accessed: Date
}
