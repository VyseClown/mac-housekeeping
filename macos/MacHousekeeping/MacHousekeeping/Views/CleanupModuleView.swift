import SwiftUI

struct CleanupModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    private var idleBytes: Int64 {
        snapshot.leftovers.filter { $0.usage == .idle }.reduce(0) { $0 + $1.bytes }
    }

    private var heldBytes: Int64 {
        snapshot.leftovers.filter { $0.usage == .inUse }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.leftovers.isEmpty {
                    EmptyStateView(
                        title: "No leftovers mapped",
                        detail: "Investigation folders that match the collector stay here. nightshift and ai-memory never appear."
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Cleanup leftovers")
            .navigationDestination(item: $model.selectedLeftoverID) { id in
                if let leftover = snapshot.leftovers.first(where: { $0.id == id }) {
                    leftoverDetail(leftover)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 28) {
                    SpaceRingView(
                        idle: idleBytes,
                        held: heldBytes,
                        caption: "leftovers only"
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Idle \(ByteFormat.string(idleBytes))")
                            .foregroundStyle(Chrome.leftoversHue)
                        Text("In use \(ByteFormat.string(heldBytes))")
                            .foregroundStyle(Chrome.amber)
                        Text("Media and worktrees stay on their own tabs.")
                            .font(.caption)
                            .foregroundStyle(Chrome.muted)
                    }
                    .font(.callout.weight(.semibold))
                    Spacer()
                }
                ForEach(snapshot.leftovers) { leftover in
                    Button {
                        model.selectedLeftoverID = leftover.id
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: leftover.kind == .investigation ? "folder.fill" : "photo")
                                .foregroundStyle(Chrome.leftoversHue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text((leftover.path as NSString).lastPathComponent)
                                    .font(.headline)
                                    .foregroundStyle(Chrome.text)
                                Text(leftover.path)
                                    .font(.caption)
                                    .foregroundStyle(Chrome.muted)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(ByteFormat.string(leftover.bytes))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Chrome.text)
                                    Text("\(leftover.openHandles.count) handles")
                                        .font(.caption)
                                        .foregroundStyle(Chrome.faint)
                                    UsageBadge(usage: leftover.usage)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Chrome.faint)
                        }
                        .padding(12)
                        .housekeepingCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
    }

    private func leftoverDetail(_ leftover: Leftover) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("← Back") { model.selectedLeftoverID = nil }
                    .buttonStyle(QuietButtonStyle())
                Text((leftover.path as NSString).lastPathComponent)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                Text(leftover.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Chrome.muted)
                    .textSelection(.enabled)
                Text(leftover.note)
                    .font(.callout)
                    .foregroundStyle(Chrome.text)
                ValidationPanel(
                    usage: leftover.usage,
                    usageReason: leftover.usageReason,
                    lastAccess: leftover.lastAccessAt,
                    lastAccessSource: leftover.lastAccessSource,
                    handles: leftover.openHandles,
                    parent: leftover.openHandles.first.map { $0.process },
                    extra: leftover.usage == .idle
                        ? "Idle leftover. Review delete later. This app does not remove files."
                        : "Delete stays locked until handles are gone and usage reads idle."
                )
                if leftover.usage == .idle {
                    Button("Review delete") { model.askDeleteLeftover(leftover) }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("In-use leftovers stay locked.")
                        .font(.caption)
                        .foregroundStyle(Chrome.amber)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Leftover")
        .navigationBarBackButtonHidden(false)
    }
}
