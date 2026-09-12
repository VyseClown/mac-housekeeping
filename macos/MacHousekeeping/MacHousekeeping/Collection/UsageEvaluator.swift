import Foundation

enum UsageEvaluator {
    static func pathUsage(
        openHandles: [OpenHandle],
        lastAccessAt: Date,
        protectedPath: Bool,
        handleScanFailed: Bool = false,
        now: Date = Date()
    ) -> (UsageState, String) {
        if protectedPath {
            return (.protected, "Matches nightshift or ai-memory. Kept. Never flagged.")
        }
        if handleScanFailed {
            return (.inUse, "Handle scan timed out. Treated as in use until proven idle.")
        }
        if !openHandles.isEmpty {
            let holders = Array(Set(openHandles.map(\.process))).sorted().joined(separator: ", ")
            let plural = openHandles.count == 1 ? "handle" : "handles"
            return (.inUse, "Open \(plural) from \(holders).")
        }
        let age = now.timeIntervalSince(lastAccessAt) / 86_400
        if age < 2 {
            return (.recent, "No open handles, but last access is under two days. Review before delete.")
        }
        return (.idle, "No open handles. Last access \(Int(age.rounded())) days ago. Looks unused.")
    }

    static func processUsage(
        cpu: Double,
        heldCleanupCount: Int,
        protectedProcess: Bool,
        inUseByModels: Bool,
        idleLeftover: Bool
    ) -> (UsageState, String) {
        if protectedProcess {
            return (.protected, "nightshift or ai-memory process. Do not kill.")
        }
        if inUseByModels {
            return (.inUse, "Models are using this process. Leave it running.")
        }
        if heldCleanupCount > 0 && cpu > 0.5 {
            return (.inUse, "Holding leftover files and consuming CPU.")
        }
        if idleLeftover && cpu < 0.3 {
            return (.idle, "Orphaned leftover with near-zero CPU. Candidate to localize and kill.")
        }
        if cpu < 0.2 && heldCleanupCount == 0 {
            return (.recent, "Quiet, but not classified as a leftover. Inspect parent and files first.")
        }
        return (.inUse, "Active developer process. Do not treat as leftover.")
    }
}
