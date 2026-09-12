import Foundation

enum Protection {
    static let blockedNames = [
        "nightshift", "night-shift", "night_shift",
        "ai-memory", "ai_memory",
    ]

    static func blocks(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return blockedNames.contains { lowered.contains($0) }
    }

    static func blocksProcess(name: String, command: String) -> Bool {
        blocks(name) || blocks(command)
    }

    static func keeps(home: String) -> [ProtectedKeep] {
        [
            ProtectedKeep(
                path: "\(home)/nightshift",
                label: "nightshift",
                reason: "Installed on purpose. Never a cleanup candidate.",
                present: true
            ),
            ProtectedKeep(
                path: "\(home)/ai-memory",
                label: "ai-memory",
                reason: "Installed on purpose. Never a cleanup candidate.",
                present: true
            ),
        ]
    }

    static func rejecting<T>(_ items: [T], path: (T) -> String) -> [T] {
        items.filter { !blocks(path($0)) }
    }
}
