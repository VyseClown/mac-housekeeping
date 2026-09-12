import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var loadState: LoadState = .idle
    @Published var focus = DashboardFocus()
    @Published var pendingConfirm: DestructiveIntent?
    @Published var banner: String?
    @Published var isScanning = false
    @Published var pendingModules: Set<HousekeepingModule> = []

    private var scanRunning = false

    var snapshot: Snapshot? {
        if case .ready(let snapshot) = loadState { return snapshot }
        return nil
    }

    func applyPartial(_ partial: ScanPartial) {
        loadState = .ready(partial.snapshot)
        pendingModules = partial.pending
        banner = partial.snapshot.warnings.first
    }

    func scan() {
        if scanRunning { return }
        scanRunning = true
        isScanning = true
        banner = nil
        if snapshot == nil {
            loadState = .loading
            pendingModules = Set(HousekeepingModule.allCases)
        }

        let sink = MainPartialSink(model: self)
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                SnapshotStore.load { partial in
                    sink.publish(partial)
                }
            }.value
            loadState = .ready(loaded)
            pendingModules = []
            banner = loaded.warnings.first
            isScanning = false
            scanRunning = false
        }
    }

    func show(_ next: HousekeepingModule) {
        focus = DashboardFocus(module: next)
    }

    func askDeleteLeftover(_ leftover: Leftover) {
        guard leftover.usage == .idle else {
            banner = "Delete stays locked until handles are gone and usage reads idle."
            return
        }
        pendingConfirm = .deleteLeftover(id: leftover.id)
    }

    func askKill(_ process: MappedProcess) {
        guard !process.inUseByModels, process.usage == .idle, process.category != .protected else {
            banner = process.localizeSignal
            return
        }
        pendingConfirm = .killProcess(pid: process.pid)
    }

    func cancelConfirm() {
        pendingConfirm = nil
    }

    func confirmPending() {
        guard let pendingConfirm, let snapshot else { return }
        switch pendingConfirm {
        case .deleteLeftover(let id):
            guard let leftover = snapshot.leftovers.first(where: { $0.id == id }) else { break }
            banner = "Nothing was deleted. Review only. \(leftover.path) is still on disk."
        case .killProcess(let pid):
            guard let process = snapshot.processes.first(where: { $0.pid == pid }) else { break }
            banner = "No signal was sent. \(process.name) (\(pid)) is still running. Localize it first."
        }
        self.pendingConfirm = nil
    }
}

final class MainPartialSink: @unchecked Sendable {
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func publish(_ partial: ScanPartial) {
        DispatchQueue.main.async { [weak model] in
            model?.applyPartial(partial)
        }
    }
}
