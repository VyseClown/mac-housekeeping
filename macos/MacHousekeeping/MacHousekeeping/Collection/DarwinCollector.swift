import Foundation

enum DarwinCollector {
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

        let leftovers = collectLeftovers(home: home, warnings: &warnings)
        let media = collectMedia(home: home, warnings: &warnings)
        let workspaces = collectWorkspaces(home: home, warnings: &warnings)
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

    private static func collectLeftovers(home: String, warnings: inout [String]) -> [Leftover] {
        let roots = [
            "\(home)/Downloads",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "/tmp",
        ].filter { FileManager.default.fileExists(atPath: $0) }

        let names = [
            "*investigation*", "*repro-har*", "*repro-screen*", "*already-used*",
        ]
        var args = roots + ["-maxdepth", "4", "("]
        for (index, name) in names.enumerated() {
            if index > 0 { args.append("-o") }
            args.append(contentsOf: ["-iname", name])
        }
        args.append(")")
        let found = run("find", args)
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty && !Protection.blocks($0) && !isMediaPath($0) }

        if found.isEmpty {
            warnings.append("No investigation leftover folders matched on this Mac.")
        }

        return found.map { path in
            let handles = handlesFor(path)
            let access = lastAccess(path)
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false
            )
            return Leftover(
                id: slug(path),
                path: path,
                kind: .investigation,
                bytes: pathBytes(path),
                lastAccessAt: access,
                lastAccessSource: "stat",
                openHandles: handles,
                usage: usage.0,
                usageReason: usage.1,
                note: "Investigation leftover. Eligible only after usage validates idle."
            )
        }
    }

    private static func collectMedia(home: String, warnings: inout [String]) -> [MediaEvidence] {
        let desktop = "\(home)/Desktop"
        guard FileManager.default.fileExists(atPath: desktop) else {
            warnings.append("Desktop is missing. Media list is empty.")
            return []
        }

        let args = [
            desktop, "-maxdepth", "5", "-type", "f", "(",
            "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
            "-o", "-iname", "*.heic", "-o", "-iname", "*.webp",
            "-o", "-iname", "*.mov", "-o", "-iname", "*.mp4", "-o", "-iname", "*.m4v",
            ")",
        ]
        let found = run("find", args)
            .split(separator: "\n")
            .map { String($0) }
            .filter { path in
                !path.isEmpty
                    && !Protection.blocks(path)
                    && looksLikeEvidence(path)
            }

        if found.isEmpty {
            warnings.append("No Desktop prove or evidence media matched on this Mac.")
        }

        return found.map { path in
            let handles = handlesFor(path)
            let access = lastAccess(path)
            let usage = UsageEvaluator.pathUsage(
                openHandles: handles,
                lastAccessAt: access,
                protectedPath: false
            )
            let filename = (path as NSString).lastPathComponent
            let holder = handles.first.map {
                ProcessRef(pid: $0.pid, name: $0.process, parentName: "unknown")
            }
            return MediaEvidence(
                id: slug(path),
                path: path,
                filename: filename,
                kind: isVideo(path) ? .video : .image,
                bytes: pathBytes(path),
                lastAccessAt: access,
                lastAccessSource: "stat",
                usage: usage.0,
                usageReason: usage.1,
                alreadyUsedOnPR: true,
                pullRequest: inferredPR(path),
                holder: holder,
                caption: "Already-used Desktop evidence. Eligible only after usage validates idle."
            )
        }
    }

    private static func collectWorkspaces(home: String, warnings: inout [String]) -> [GitWorkspace] {
        let repoRoots = discoverRepos(home: home)
        if repoRoots.isEmpty {
            warnings.append("No git repositories found under the home folder or /tmp.")
        }

        var workspaces: [GitWorkspace] = []
        var seenPaths = Set<String>()

        for repo in repoRoots {
            if Protection.blocks(repo) { continue }
            let porcelain = run("git", ["-C", repo, "worktree", "list", "--porcelain"])
            let blocks = porcelain.components(separatedBy: "\n\n")
            for block in blocks {
                let lines = block.split(separator: "\n").map(String.init)
                guard let worktreeLine = lines.first(where: { $0.hasPrefix("worktree ") }) else { continue }
                let path = String(worktreeLine.dropFirst("worktree ".count))
                if seenPaths.contains(path) || Protection.blocks(path) { continue }
                seenPaths.insert(path)
                let branch = lines.first(where: { $0.hasPrefix("branch ") })
                    .map { String($0.dropFirst("branch ".count)).replacingOccurrences(of: "refs/heads/", with: "") }
                    ?? (lines.contains(where: { $0 == "bare" }) ? "(bare)" : "detached")
                let handles = handlesFor(path)
                let holder = handles.first.map {
                    ProcessRef(pid: $0.pid, name: $0.process, parentName: "unknown")
                }
                let usage = UsageEvaluator.pathUsage(
                    openHandles: handles,
                    lastAccessAt: lastAccess(path),
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
                        bytes: pathBytes(path),
                        usage: usage.0,
                        usageReason: usage.1,
                        holdingProcess: holder,
                        suggestedAction: .removeWorktreeLater(command: "git worktree remove \(path)")
                    )
                )
            }

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

        return workspaces.sorted { $0.bytes > $1.bytes }
    }

    private static func collectProcesses(cleanupPaths: [String], warnings: inout [String]) -> [MappedProcess] {
        let output = run("ps", ["-axo", "pid=,ppid=,user=,pcpu=,pmem=,rss=,etime=,state=,command="])
        if output.isEmpty {
            warnings.append("ps failed. Process list is empty.")
            return []
        }

        let filter = try? NSRegularExpression(
            pattern: "Simulator|launchd_sim|qemu-system|CoreSimulator|Xcode|SourceKit|node|Cursor|ffmpeg|tcpdump|Preview|nightshift|ai-memory|ai_memory"
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
            let held = filesForPid(row.pid, cleanupPaths: cleanupPaths)
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
        let roots = ["\(home)/src", "\(home)/Developer", "\(home)/Projects", "\(home)/code", home, "/tmp"]
            .filter { FileManager.default.fileExists(atPath: $0) }
        let output = run("find", roots + ["-maxdepth", "4", "-name", ".git"])
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

    private static func filesForPid(_ pid: Int, cleanupPaths: [String]) -> [HeldFile] {
        let output = run("lsof", ["-nP", "-p", String(pid)])
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
            of: "investigation|repro-har|repro-screen|used-capture|used-export|used-review|already-used|pr-evidence|prove-|evidence-",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isMediaPath(_ path: String) -> Bool {
        isVideo(path) || path.range(of: "\\.(png|jpe?g|heic|webp)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isVideo(_ path: String) -> Bool {
        path.range(of: "\\.(mov|mp4|m4v)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func inferredPR(_ path: String) -> String? {
        if let match = path.range(of: "pr-(\\d+)", options: .regularExpression) {
            let digits = path[match].split(separator: "-").last.map(String.init) ?? ""
            return digits.isEmpty ? nil : "PR #\(digits)"
        }
        return nil
    }

    private static func handlesFor(_ path: String) -> [OpenHandle] {
        let output = run("lsof", ["-nP", "--", path])
        var handles: [OpenHandle] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, let pid = Int(parts[1]) else { continue }
            handles.append(OpenHandle(pid: pid, process: parts[0], fd: parts[3], mode: parts.count > 4 ? parts[4] : nil))
        }
        return handles
    }

    private static func pathBytes(_ path: String) -> Int64 {
        let output = run("du", ["-sk", path])
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
    private static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launchPath] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
