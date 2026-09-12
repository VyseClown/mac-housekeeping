import Foundation

enum DarwinCollector {
    static let leftoverNameGlobs = [
        "*investigation*", "*repro*", "*already-used*",
        "*evidence*", "*prove*", "*artifacts*",
        "pr-*", "PR-*", "*recording*", "*demo-live*",
        "*sbs*", "*walkthrough*", "*overlay*",
    ]
    static let mediaVideoLimit = 48
    static let mediaImageLimit = 24
    static let duParallelLimit = 4
    static let worktreeDuTimeout: Double = 15

    static func leftoverNamePattern() -> String {
        "investigation|repro|already-used|evidence|prove|artifacts|pr-|recording|demo-live|sbs|walkthrough|overlay"
    }

    static func looksLikeLeftoverName(_ name: String) -> Bool {
        name.range(
            of: leftoverNamePattern(),
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func looksLikeWorktreeFolderName(_ name: String) -> Bool {
        name.contains("cursor-worktree")
    }

    static func desktopLeftoverDirectories(from paths: [String]) -> [String] {
        paths.filter { looksLikeLeftoverName(($0 as NSString).lastPathComponent) }
    }

    static func leftoverSearchRootCandidates(home: String) -> [String] {
        [
            "\(home)/Downloads",
            "\(home)/Documents",
            "/tmp",
            "/private/tmp",
        ]
    }

    static func leftoverSearchRoots(home: String) -> [String] {
        uniqueExistingPaths(leftoverSearchRootCandidates(home: home))
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
        try collect(onPartial: nil)
    }

    static func collect(onPartial: (@Sendable (ScanPartial) -> Void)?) throws -> Snapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let user = NSUserName()
        let host = hostInfo(user: user)
        let desktop = "\(home)/Desktop"
        let keeps = Protection.keeps(home: home).map { keep in
            var copy = keep
            copy.present = FileManager.default.fileExists(atPath: keep.path)
            return copy
        }

        let box = ScanBox(host: host, keeps: keeps)
        let publish: @Sendable () -> Void = {
            onPartial?(box.partial())
        }

        let queue = DispatchQueue.global(qos: .userInitiated)
        let discovery = DispatchGroup()
        let psReady = DispatchGroup()
        let done = DispatchGroup()

        discovery.enter()
        queue.async {
            box.desktopWalk = walkDesktop(desktop)
            discovery.leave()
        }

        discovery.enter()
        queue.async {
            box.namedLeftoverPaths = findNamedLeftoverPaths(home: home)
            discovery.leave()
        }

        discovery.enter()
        done.enter()
        queue.async {
            var warnings: [String] = []
            let drafts = collectWorkspaceDrafts(home: home, warnings: &warnings)
            box.addWarnings(warnings)
            box.workspaces = drafts
            box.markReady(.worktrees)
            publish()
            discovery.leave()
            box.workspaces = applyWorktreeSizes(drafts)
            publish()
            done.leave()
        }

        done.enter()
        queue.async {
            var warnings: [String] = []
            box.simulators = collectSimulators(warnings: &warnings)
            box.addWarnings(warnings)
            box.markSimulatorsReady()
            publish()
            done.leave()
        }

        psReady.enter()
        done.enter()
        queue.async {
            var warnings: [String] = []
            let rows = collectProcessRows(warnings: &warnings)
            box.addWarnings(warnings)
            box.processRows = rows
            box.processes = buildProcesses(rows: rows, heldByPid: [:])
            box.markProcessesListed()
            publish()
            psReady.leave()
            done.leave()
        }

        discovery.wait()
        var leftoverWarnings: [String] = []
        let worktreePaths = box.worktreePaths
        let leftovers = assembleLeftovers(
            desktopWalk: box.desktopWalk,
            namedPaths: box.namedLeftoverPaths,
            excluding: worktreePaths,
            warnings: &leftoverWarnings
        )
        let media = collectMedia(desktopWalk: box.desktopWalk, warnings: &leftoverWarnings)
        box.addWarnings(leftoverWarnings)
        box.leftovers = leftovers
        box.media = media
        box.markReady(.leftovers)
        box.markReady(.media)
        publish()

        psReady.wait()
        let cleanupPaths = leftovers.map(\.path) + media.map(\.path) + Array(worktreePaths)
        let inspectPids = box.processes.compactMap { process -> Int? in
            shouldInspect(name: process.name, command: process.command) ? process.pid : nil
        }
        let held = filesForPids(inspectPids, cleanupPaths: cleanupPaths)
        box.processes = buildProcesses(rows: box.processRows, heldByPid: held)
        publish()

        done.wait()
        box.clearPending()
        return box.partial().snapshot
    }

    private static func assembleLeftovers(
        desktopWalk: DesktopInventory,
        namedPaths: [String],
        excluding worktreePaths: Set<String>,
        warnings: inout [String]
    ) -> [Leftover] {
        var paths = Set(desktopLeftoverDirectories(from: desktopWalk.topLevelDirectories))
        paths.formUnion(namedPaths)

        let resolvedWorktrees = Set(worktreePaths.flatMap { [$0, ($0 as NSString).resolvingSymlinksInPath] })
        let found = paths
            .filter { path in
                !Protection.blocks(path)
                    && !isMediaPath(path)
                    && !looksLikeWorktreeFolderName((path as NSString).lastPathComponent)
                    && !isGitCheckout(path)
                    && !resolvedWorktrees.contains(path)
                    && !resolvedWorktrees.contains((path as NSString).resolvingSymlinksInPath)
            }
            .sorted()

        if found.isEmpty {
            warnings.append("No leftover folders matched on this Mac.")
        }

        let handleScan = handlesForPaths(found)
        let desktopRoot = desktopWalk.root
        let desktopPrefix = desktopRoot.hasSuffix("/") ? desktopRoot : desktopRoot + "/"
        let offDesktop = found.filter { path in
            path != desktopRoot && !path.hasPrefix(desktopPrefix)
        }
        let sized = parallelPathBytes(offDesktop)

        return found.map { path in
            let onDesktop = path == desktopRoot || path.hasPrefix(desktopPrefix)
            let bytes: Int64
            if onDesktop {
                bytes = desktopWalk.directoryBytes[path]
                    ?? desktopWalk.directoryBytes[(path as NSString).resolvingSymlinksInPath]
                    ?? 0
            } else if let sizedHit = sized[path] {
                bytes = sizedHit.timedOut ? 0 : sizedHit.bytes
            } else {
                bytes = 0
            }
            let failed = handleScan.timedOut.contains(path)
            let handles = handleScan.handles[path] ?? []
            let access = lastAccess(path)
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false,
                handleScanFailed: failed
            )
            var reason = usage.1
            if !onDesktop, let sizedHit = sized[path], sizedHit.timedOut {
                reason += " Size scan timed out; size unknown."
            }
            return Leftover(
                id: slug(path),
                path: path,
                kind: .investigation,
                bytes: bytes,
                lastAccessAt: access,
                lastAccessSource: "stat",
                openHandles: failed ? [] : handles,
                usage: usage.0,
                usageReason: reason,
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

        let handleScan = handlesForPaths(picked.map(\.path))
        return picked.map { hit in
            let failed = handleScan.timedOut.contains(hit.path)
            let handles = handleScan.handles[hit.path] ?? []
            let access = hit.accessed
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false,
                handleScanFailed: failed
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

    private static func collectWorkspaceDrafts(home: String, warnings: inout [String]) -> [GitWorkspace] {
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
                appendLeftoverWorktree(
                    path: orphan,
                    repo: orphan,
                    branch: (orphan as NSString).lastPathComponent,
                    prunable: false,
                    seenPaths: &seenPaths,
                    into: &workspaces
                )
            } else {
                appendWorktrees(from: porcelain, repo: orphan, seenPaths: &seenPaths, into: &workspaces)
            }
        }

        return workspaces
    }

    private static func applyWorktreeSizes(_ workspaces: [GitWorkspace]) -> [GitWorkspace] {
        let leftover = workspaces.filter { workspace in
            workspace.kind == .worktree
                && isTmpPath(workspace.path)
                && FileManager.default.fileExists(atPath: workspace.path)
                && !workspace.usageReason.contains("Missing or prunable")
        }
        let paths = leftover.map(\.path)
        let handleScan = handlesForPaths(paths)
        let sized = parallelPathBytes(paths, timeoutSeconds: worktreeDuTimeout)
        return workspaces.map { workspace in
            guard leftover.contains(where: { $0.id == workspace.id }) else { return workspace }
            var copy = workspace
            if let sizedHit = sized[workspace.path], sizedHit.timedOut {
                copy.bytes = 0
                copy.usageReason = "Size scan timed out. Size unknown."
            } else {
                copy.bytes = sized[workspace.path]?.bytes ?? 0
            }
            let failed = handleScan.timedOut.contains(workspace.path)
            let handles = handleScan.handles[workspace.path] ?? []
            let access = lastAccess(workspace.path)
            copy.lastAccessAt = access
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false,
                handleScanFailed: failed
            )
            if !failed {
                copy.usage = usage.0
                if !(sized[workspace.path]?.timedOut ?? false) {
                    copy.usageReason = usage.1
                }
                copy.holdingProcess = handles.first.map {
                    ProcessRef(pid: $0.pid, name: $0.process, parentName: "unknown")
                }
            } else {
                copy.usage = usage.0
                copy.usageReason = usage.1
            }
            return copy
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func collectProcessRows(warnings: inout [String]) -> [ProcessRow] {
        let output = run("ps", ["-axo", "pid=,ppid=,user=,pcpu=,pmem=,rss=,etime=,state=,command="])
        if output.isEmpty {
            warnings.append("ps failed. Process list is empty.")
            return []
        }

        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count >= 9,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let cpu = Double(parts[3]),
                  let rss = Int(parts[5])
            else { continue }
            rows.append(
                ProcessRow(
                    pid: pid,
                    ppid: ppid,
                    user: String(parts[2]),
                    cpu: cpu,
                    memMb: rss / 1024,
                    elapsed: String(parts[6]),
                    state: String(parts[7]),
                    command: String(parts[8])
                )
            )
        }
        return rows
    }

    private static func buildProcesses(
        rows: [ProcessRow],
        heldByPid: [Int: [HeldFile]]
    ) -> [MappedProcess] {
        let filter = try? NSRegularExpression(
            pattern: "Simulator|launchd_sim|qemu-system|CoreSimulator|Xcode|SourceKit|node|Cursor|ffmpeg|tcpdump|Preview|QuickTime|QTKit|VLC|nightshift|night-shift|ai-memory|ai_memory"
        )
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
            let held = heldByPid[row.pid] ?? []
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

    private static func shouldInspect(name: String, command: String) -> Bool {
        command.contains("/tmp")
            || command.contains("/Desktop")
            || command.contains("investigation")
            || name.range(of: "QuickTime|QTKit|Preview|ffmpeg|qemu", options: .regularExpression) != nil
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

    private static func findNamedLeftoverPaths(home: String) -> [String] {
        let roots = leftoverSearchRoots(home: home)
        guard !roots.isEmpty else { return [] }
        var args = roots + ["-maxdepth", "3", "("]
        for (index, name) in leftoverNameGlobs.enumerated() {
            if index > 0 { args.append("-o") }
            args.append(contentsOf: ["-iname", name])
        }
        args.append(")")
        var paths: [String] = []
        for path in run("find", args + ["-type", "d"], timeoutSeconds: 25)
            .split(separator: "\n").map(String.init)
        {
            guard !path.isEmpty else { continue }
            if looksLikeWorktreeFolderName((path as NSString).lastPathComponent) { continue }
            if isGitCheckout(path) { continue }
            paths.append(path)
        }
        return paths
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
            let prunable = lines.contains(where: { $0 == "prunable" })
            appendLeftoverWorktree(
                path: path,
                repo: repo,
                branch: branch,
                prunable: prunable,
                seenPaths: &seenPaths,
                into: &workspaces
            )
        }
    }

    private static func appendLeftoverWorktree(
        path: String,
        repo: String,
        branch: String,
        prunable: Bool,
        seenPaths: inout Set<String>,
        into workspaces: inout [GitWorkspace]
    ) {
        let resolved = (path as NSString).resolvingSymlinksInPath
        if seenPaths.contains(path) || seenPaths.contains(resolved) || Protection.blocks(path) { return }
        seenPaths.insert(path)
        seenPaths.insert(resolved)
        let leftoverTree = isTmpPath(path)
        let exists = FileManager.default.fileExists(atPath: path)
        let skipExpensive = prunable || !exists
        workspaces.append(
            GitWorkspace(
                id: slug(path),
                kind: .worktree,
                name: branch,
                path: path,
                repoName: (repo as NSString).lastPathComponent,
                repoRoot: repo,
                bytes: 0,
                usage: .recent,
                usageReason: skipExpensive
                    ? "Missing or prunable. Size skipped."
                    : leftoverTree
                        ? "Leftover checkout. Size still collecting."
                        : "Active checkout. Listed for review; size is left on the leftover /tmp slice.",
                holdingProcess: nil,
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

    private static func filesForPids(_ pids: [Int], cleanupPaths: [String]) -> [Int: [HeldFile]] {
        guard !pids.isEmpty else { return [:] }
        var heldByPid: [Int: [HeldFile]] = [:]
        for chunk in chunks(pids, size: 32) {
            let result = runDetailed("lsof", ["-nP", "-p", chunk.map(String.init).joined(separator: ",")], timeoutSeconds: 8)
            var seen = [Int: Set<String>]()
            for line in result.output.split(separator: "\n").dropFirst() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 9, let pid = Int(parts[1]) else { continue }
                let path = parts.dropFirst(8).joined(separator: " ")
                guard path.hasPrefix("/") else { continue }
                if seen[pid, default: []].contains(path) { continue }
                let interesting = looksLikeEvidence(path)
                    || path.contains("investigation")
                    || path.contains("CoreSimulator")
                    || path.contains("DerivedData")
                    || path.contains("worktree")
                    || Protection.blocks(path)
                if !interesting { continue }
                seen[pid, default: []].insert(path)
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
                var list = heldByPid[pid] ?? []
                if list.count >= 6 { continue }
                list.append(HeldFile(path: path, role: role, bytes: nil))
                heldByPid[pid] = list
            }
        }
        return heldByPid
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

    private static func isTmpPath(_ path: String) -> Bool {
        path.contains("/tmp/") || path.contains("/private/tmp/")
    }

    private static func isGitCheckout(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
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

    private static func handlesForPaths(_ paths: [String]) -> HandleScan {
        var handles: [String: [OpenHandle]] = [:]
        var timedOut = Set<String>()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        for chunk in chunks(existing, size: 24) {
            let result = runDetailed("lsof", ["-nP", "--"] + chunk, timeoutSeconds: 8)
            var seenInChunk = Set<String>()
            for line in result.output.split(separator: "\n").dropFirst() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 9, let pid = Int(parts[1]) else { continue }
                let name = parts.dropFirst(8).joined(separator: " ")
                guard let match = chunk.first(where: { name == $0 || name.hasPrefix($0) || $0.hasPrefix(name) }) else {
                    continue
                }
                seenInChunk.insert(match)
                handles[match, default: []].append(
                    OpenHandle(pid: pid, process: parts[0], fd: parts[3], mode: parts.count > 4 ? parts[4] : nil)
                )
            }
            if result.timedOut {
                for path in chunk where handles[path] == nil {
                    timedOut.insert(path)
                }
            }
            _ = seenInChunk
        }
        return HandleScan(handles: handles, timedOut: timedOut)
    }

    private static func parallelPathBytes(_ paths: [String], timeoutSeconds: Double = 15) -> [String: SizedPath] {
        guard !paths.isEmpty else { return [:] }
        var result: [String: SizedPath] = [:]
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: duParallelLimit)
        let group = DispatchGroup()
        for path in paths {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                let sized = pathBytes(path, timeoutSeconds: timeoutSeconds)
                lock.lock()
                result[path] = sized
                lock.unlock()
                semaphore.signal()
                group.leave()
            }
        }
        group.wait()
        return result
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

    private static func pathBytes(_ path: String, timeoutSeconds: Double = 15) -> SizedPath {
        let result = runDetailed("du", ["-sk", path], timeoutSeconds: timeoutSeconds)
        if result.timedOut {
            return SizedPath(bytes: 0, timedOut: true)
        }
        let kb = Int64(result.output.split(separator: "\t").first ?? result.output.split(separator: " ").first ?? "0") ?? 0
        return SizedPath(bytes: kb * 1024, timedOut: false)
    }

    private static func lastAccess(_ path: String) -> Date {
        let url = URL(fileURLWithPath: path)
        if let date = try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate {
            return date
        }
        return Date(timeIntervalSince1970: 0)
    }

    private static func slug(_ path: String) -> String {
        let raw = path.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return String(raw.trimmingCharacters(in: CharacterSet(charactersIn: "-")).suffix(48))
    }

    private static func chunks<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        var result: [[T]] = []
        var index = 0
        while index < items.count {
            result.append(Array(items[index..<min(index + size, items.count)]))
            index += size
        }
        return result
    }

    private static let hostCacheLock = NSLock()
    private static var cachedHost: HostInfo?

    private static func hostInfo(user: String) -> HostInfo {
        hostCacheLock.lock()
        defer { hostCacheLock.unlock() }
        if let cachedHost { return cachedHost }
        let hostname = run("scutil", ["--get", "ComputerName"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let osVersion = run("sw_vers", ["-productVersion"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let info = HostInfo(
            hostname: hostname.isEmpty ? ProcessInfo.processInfo.hostName : hostname,
            os: osVersion.isEmpty ? "macOS" : "macOS \(osVersion)",
            user: user
        )
        cachedHost = info
        return info
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String], timeoutSeconds: Double = 30) -> String {
        runDetailed(launchPath, arguments, timeoutSeconds: timeoutSeconds).output
    }

    private static func runDetailed(_ launchPath: String, _ arguments: [String], timeoutSeconds: Double = 30) -> CommandResult {
        let process = Process()
        let resolved = resolveCommand(launchPath)
        if resolved.contains("/") {
            process.executableURL = URL(fileURLWithPath: resolved)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [launchPath] + arguments
        }
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
            return CommandResult(output: "", timedOut: false)
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        let timedOut = group.wait(timeout: .now() + timeoutSeconds) == .timedOut
        if timedOut, process.isRunning {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        let tail = stdout.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        buffer.append(tail)
        let data = Data(referencing: buffer)
        lock.unlock()
        return CommandResult(output: String(data: data, encoding: .utf8) ?? "", timedOut: timedOut)
    }

    private static func resolveCommand(_ name: String) -> String {
        if name.hasPrefix("/") { return name }
        let candidates = [
            "/usr/bin/\(name)",
            "/usr/sbin/\(name)",
            "/bin/\(name)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return name
    }
}

private final class ScanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var host: HostInfo
    private var keeps: [ProtectedKeep]
    var desktopWalk = DesktopInventory(root: "", topLevelDirectories: [], directoryBytes: [:], media: [])
    var namedLeftoverPaths: [String] = []
    private var _workspaces: [GitWorkspace] = []
    private var _leftovers: [Leftover] = []
    private var _media: [MediaEvidence] = []
    private var _processes: [MappedProcess] = []
    private var _processRows: [ProcessRow] = []
    private var _simulators: [SimulatorDevice] = []
    private var warnings: [String] = []
    private var pending = Set(HousekeepingModule.allCases)
    private var processesListed = false
    private var simulatorsListed = false

    init(host: HostInfo, keeps: [ProtectedKeep]) {
        self.host = host
        self.keeps = keeps
    }

    var workspaces: [GitWorkspace] {
        get { lock.lock(); defer { lock.unlock() }; return _workspaces }
        set { lock.lock(); _workspaces = newValue; lock.unlock() }
    }

    var leftovers: [Leftover] {
        get { lock.lock(); defer { lock.unlock() }; return _leftovers }
        set { lock.lock(); _leftovers = newValue; lock.unlock() }
    }

    var media: [MediaEvidence] {
        get { lock.lock(); defer { lock.unlock() }; return _media }
        set { lock.lock(); _media = newValue; lock.unlock() }
    }

    var processes: [MappedProcess] {
        get { lock.lock(); defer { lock.unlock() }; return _processes }
        set { lock.lock(); _processes = newValue; lock.unlock() }
    }

    var processRows: [ProcessRow] {
        get { lock.lock(); defer { lock.unlock() }; return _processRows }
        set { lock.lock(); _processRows = newValue; lock.unlock() }
    }

    var simulators: [SimulatorDevice] {
        get { lock.lock(); defer { lock.unlock() }; return _simulators }
        set { lock.lock(); _simulators = newValue; lock.unlock() }
    }

    var worktreePaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(_workspaces.filter { $0.kind == .worktree }.map(\.path))
    }

    func addWarnings(_ extra: [String]) {
        guard !extra.isEmpty else { return }
        lock.lock()
        warnings.append(contentsOf: extra)
        lock.unlock()
    }

    func markReady(_ module: HousekeepingModule) {
        lock.lock()
        pending.remove(module)
        lock.unlock()
    }

    func markProcessesListed() {
        lock.lock()
        processesListed = true
        if simulatorsListed { pending.remove(.processes) }
        lock.unlock()
    }

    func markSimulatorsReady() {
        lock.lock()
        simulatorsListed = true
        if processesListed { pending.remove(.processes) }
        lock.unlock()
    }

    func clearPending() {
        lock.lock()
        pending = []
        lock.unlock()
    }

    func partial() -> ScanPartial {
        lock.lock()
        defer { lock.unlock() }
        let leftoverBytes = _leftovers.reduce(Int64(0)) { $0 + $1.bytes }
        let mediaBytes = _media.reduce(Int64(0)) { $0 + $1.bytes }
        let worktreeBytes = _workspaces.filter { $0.kind == .worktree }.reduce(Int64(0)) { $0 + $1.bytes }
        let reclaimable =
            _leftovers.filter { $0.usage == .idle }.reduce(Int64(0)) { $0 + $1.bytes }
            + _media.filter { $0.usage == .idle }.reduce(Int64(0)) { $0 + $1.bytes }
            + _workspaces.filter { $0.usage == .idle }.reduce(Int64(0)) { $0 + $1.bytes }
        let inUse =
            _leftovers.filter { $0.usage == .inUse }.reduce(Int64(0)) { $0 + $1.bytes }
            + _media.filter { $0.usage == .inUse }.reduce(Int64(0)) { $0 + $1.bytes }
            + _workspaces.filter { $0.usage == .inUse }.reduce(Int64(0)) { $0 + $1.bytes }
        return ScanPartial(
            snapshot: Snapshot(
                collectedAt: Date(),
                source: .macos,
                host: host,
                leftovers: _leftovers,
                media: _media,
                workspaces: _workspaces,
                processes: _processes,
                simulators: _simulators,
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
            ),
            pending: pending
        )
    }
}

private struct ProcessRow {
    var pid: Int
    var ppid: Int
    var user: String
    var cpu: Double
    var memMb: Int
    var elapsed: String
    var state: String
    var command: String
}

private struct HandleScan {
    var handles: [String: [OpenHandle]]
    var timedOut: Set<String>
}

private struct SizedPath {
    var bytes: Int64
    var timedOut: Bool
}

private struct CommandResult {
    var output: String
    var timedOut: Bool
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
