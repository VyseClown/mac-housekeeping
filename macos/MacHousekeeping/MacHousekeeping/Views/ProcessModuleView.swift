import SwiftUI

struct ProcessModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    private var selected: MappedProcess? {
        snapshot.processes.first(where: { $0.pid == model.selectedProcessID }) ?? snapshot.processes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Xcode Simulators")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                    ForEach(snapshot.simulators) { device in
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

                    Text("Processes")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                        .padding(.top, 8)
                    ForEach(snapshot.processes) { process in
                        Button {
                            model.selectedProcessID = process.pid
                        } label: {
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
                            }
                            .padding(10)
                            .background(model.selectedProcessID == process.pid ? Color.white.opacity(0.06) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 420)
            Divider().background(Color.white.opacity(0.06))
            if let process = selected {
                detail(process)
            }
        }
        .onAppear {
            if model.selectedProcessID == nil {
                model.selectedProcessID = snapshot.processes.first?.pid
            }
        }
    }

    private func detail(_ process: MappedProcess) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(20)
        }
        .frame(minWidth: 320)
    }
}
