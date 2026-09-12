import XCTest
@testable import MacHousekeeping

final class InventoryInvariantTests: XCTestCase {
    func testMockMediaIsAbout28GiB() {
        let snapshot = MockInventory.snapshot()
        XCTAssertEqual(snapshot.totals.mediaBytes, 30_064_771_072)
        XCTAssertEqual(snapshot.media.reduce(0) { $0 + $1.bytes }, 30_064_771_072)
    }

    func testMockWorktreesAreAbout23GiB() {
        let snapshot = MockInventory.snapshot()
        XCTAssertEqual(snapshot.totals.worktreeBytes, 24_696_061_952)
        let worktreeSum = snapshot.workspaces.filter { $0.kind == .worktree }.reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertEqual(worktreeSum, 24_696_061_952)
    }

    func testProtectedPathsNeverAppear() {
        let snapshot = MockInventory.snapshot()
        let paths = snapshot.leftovers.map(\.path)
            + snapshot.media.map(\.path)
            + snapshot.workspaces.map(\.path)
            + snapshot.workspaces.map(\.name)
        for path in paths {
            XCTAssertFalse(Protection.blocks(path), path)
        }
        XCTAssertEqual(snapshot.protectedKeeps.map(\.label).sorted(), ["ai-memory", "nightshift"])
    }

    func testWorktreeRemoveIsSuggestionOnly() {
        let snapshot = MockInventory.snapshot()
        let actions = snapshot.workspaces.compactMap { workspace -> String? in
            if case .removeWorktreeLater(let command) = workspace.suggestedAction {
                return command
            }
            return nil
        }
        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.allSatisfy { $0.hasPrefix("git worktree remove ") })
        XCTAssertNil(
            Mirror(reflecting: SnapshotStore.self).children.first(where: { "\($0.label ?? "")".contains("remove") })
        )
    }

    func testFourPeerTabsOnly() {
        XCTAssertEqual(HousekeepingModule.allCases.map(\.rawValue), [
            "leftovers", "media", "worktrees", "processes",
        ])
    }

    func testDesktopEvidenceIsCleanupCandidate() {
        let snapshot = MockInventory.snapshot()
        XCTAssertTrue(snapshot.media.allSatisfy(\.alreadyUsedOnPR))
        XCTAssertTrue(snapshot.media.allSatisfy { $0.path.contains("/Desktop/") })
    }
}
