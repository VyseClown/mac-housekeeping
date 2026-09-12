import Foundation

enum SnapshotStore {
    static func load() -> Snapshot {
        if DarwinCollector.isDarwin() {
            do {
                return try DarwinCollector.collect()
            } catch {
                var fallback = MockInventory.snapshot()
                fallback.warnings.insert(
                    "macOS collection failed (\(error.localizedDescription)). Showing mock data.",
                    at: 0
                )
                return fallback
            }
        }
        return MockInventory.snapshot()
    }
}
