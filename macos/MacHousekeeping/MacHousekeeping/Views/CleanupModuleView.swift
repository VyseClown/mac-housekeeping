import SwiftUI

struct CleanupModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    private var selected: Leftover? {
        snapshot.leftovers.first(where: { $0.id == model.selectedLeftoverID }) ?? snapshot.leftovers.first
    }

    var body: some View {
        HStack(spacing: 0) {
            if snapshot.leftovers.isEmpty {
                EmptyStateView(
                    title: "No leftovers mapped",
                    detail: "Investigation folders that match the collector stay here. nightshift and ai-memory never appear."
                )
            } else {
                list
                Divider().background(Color.white.opacity(0.06))
                if let leftover = selected {
                    detail(leftover)
                }
            }
        }
        .onAppear {
            if model.selectedLeftoverID == nil {
                model.selectedLeftoverID = snapshot.leftovers.first?.id
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
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
                        }
                        .padding(12)
                        .background(model.selectedLeftoverID == leftover.id ? Color.white.opacity(0.06) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 380)
    }

    private func detail(_ leftover: Leftover) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        }
        .frame(minWidth: 320)
    }
}
