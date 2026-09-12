import SwiftUI

struct ProcessModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Processes")
                .navigationDestination(item: $model.focus.processID) { pid in
                    if let process = snapshot.processes.first(where: { $0.pid == pid }) {
                        detail(process)
                    }
                }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if snapshot.processes.isEmpty && snapshot.simulators.isEmpty {
                    EmptyStateView(
                        title: model.pendingModules.contains(.processes)
                            ? "Scanning processes"
                            : "No mapped developer processes",
                        detail: model.pendingModules.contains(.processes)
                            ? "ps and simctl run beside leftovers and worktrees. This tab paints when either finishes."
                            : "Simulator, Xcode, leftover captures, and holders of cleanup paths would show here."
                    )
                } else {
                    Text("Xcode Simulators")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                    if snapshot.simulators.isEmpty {
                        Text(model.pendingModules.contains(.processes)
                             ? "Simulator list still collecting."
                             : "No available simulators.")
                            .font(.caption)
                            .foregroundStyle(Chrome.muted)
                    }
                    ForEach(snapshot.simulators) { device in
                        SimulatorRow(device: device)
                    }

                    Text("Processes")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                        .padding(.top, 8)
                    if snapshot.processes.isEmpty {
                        Text(model.pendingModules.contains(.processes)
                             ? "Process list still collecting."
                             : "No mapped developer processes.")
                            .font(.caption)
                            .foregroundStyle(Chrome.muted)
                    }
                    ForEach(snapshot.processes) { process in
                        ProcessRow(process: process) {
                            model.focus.processID = process.pid
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private func detail(_ process: MappedProcess) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("← Back") { model.focus.processID = nil }
                    .buttonStyle(QuietButtonStyle())
                Text(process.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                Text(process.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Chrome.muted)
                    .textSelection(.enabled)
                ValidationPanel(
                    usage: process.usage,
                    usageReason: process.usageReason,
                    lastAccess: nil,
                    lastAccessSource: nil,
                    handles: [],
                    parent: "\(process.parentName) (\(process.ppid))",
                    extra: process.localizeSignal
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Localize")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                    Text(process.localizeActivityMonitor)
                    Text(process.localizeInspect)
                    Text(process.localizeSignal)
                }
                .font(.caption)
                .foregroundStyle(Chrome.muted)

                if !process.heldFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Holds")
                            .font(.headline)
                            .foregroundStyle(Chrome.text)
                        ForEach(process.heldFiles, id: \.path) { file in
                            Text(file.path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Chrome.text)
                        }
                    }
                }

                if process.usage == .idle && !process.inUseByModels {
                    Button("Localize, then kill") { model.askKill(process) }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("Kill stays locked. Localize first, or leave models and protected processes running.")
                        .font(.caption)
                        .foregroundStyle(Chrome.amber)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Process")
    }
}

struct SimulatorRow: View, Equatable {
    var device: SimulatorDevice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                Text("\(device.runtime) · \(device.state.rawValue)")
                    .font(.caption)
                    .foregroundStyle(Chrome.muted)
                Text(device.note)
                    .font(.caption2)
                    .foregroundStyle(Chrome.faint)
            }
            Spacer()
            Button("Close") {}
                .disabled(true)
                .buttonStyle(QuietButtonStyle())
                .opacity(0.45)
        }
        .padding(12)
        .housekeepingCard()
    }
}

struct ProcessRow: View, Equatable {
    var process: MappedProcess
    var action: () -> Void

    static func == (lhs: ProcessRow, rhs: ProcessRow) -> Bool {
        lhs.process == rhs.process
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(process.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Chrome.text)
                    Text("PID \(process.pid) · parent \(process.parentName)")
                        .font(.caption)
                        .foregroundStyle(Chrome.muted)
                }
                Spacer()
                Text(String(format: "%.1f cpu", process.cpu))
                    .font(.caption)
                    .foregroundStyle(Chrome.faint)
                UsageBadge(usage: process.usage)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Chrome.faint)
            }
            .padding(12)
            .housekeepingCard()
        }
        .buttonStyle(.plain)
    }
}
