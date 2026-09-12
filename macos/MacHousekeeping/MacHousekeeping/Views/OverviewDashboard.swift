import SwiftUI

struct OverviewDashboard: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 36) {
                    SpaceRingView(
                        leftovers: snapshot.totals.leftoverBytes,
                        media: snapshot.totals.mediaBytes,
                        worktrees: snapshot.totals.worktreeBytes
                    )
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Space map")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Chrome.text)
                        Text("Investigation leftovers, already-used Desktop evidence, and /tmp git worktrees. nightshift and ai-memory stay off this map.")
                            .font(.callout)
                            .foregroundStyle(Chrome.muted)
                            .frame(maxWidth: 420, alignment: .leading)
                        legend
                        Button("Review leftovers") { model.reviewLeftovers() }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 6)
                    }
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    CategoryCard(
                        title: "Cleanup leftovers",
                        size: ByteFormat.string(snapshot.totals.leftoverBytes),
                        detail: "\(snapshot.leftovers.count) folders with usage proof",
                        symbol: "internaldrive",
                        hue: Chrome.leftoversHue
                    ) { model.module = .leftovers }
                    CategoryCard(
                        title: "Desktop media",
                        size: ByteFormat.string(snapshot.totals.mediaBytes),
                        detail: "\(snapshot.media.count) prove and evidence files already used on PRs",
                        symbol: "photo.on.rectangle.angled",
                        hue: Chrome.mediaHue
                    ) { model.module = .media }
                    CategoryCard(
                        title: "Branches and worktrees",
                        size: ByteFormat.string(snapshot.totals.worktreeBytes),
                        detail: "\(snapshot.workspaces.filter { $0.kind == .worktree }.count) worktrees. Remove is a later suggestion only.",
                        symbol: "arrow.triangle.branch",
                        hue: Chrome.worktreeHue
                    ) { model.module = .worktrees }
                }

                HStack(spacing: 14) {
                    stat("Reclaimable if idle", ByteFormat.string(snapshot.totals.reclaimableBytes), Chrome.accent)
                    stat("Held in use", ByteFormat.string(snapshot.totals.inUseBytes), Chrome.amber)
                    stat("Protected keeps", "\(snapshot.totals.protectedCount)", Chrome.muted)
                    stat("Simulators listed", "\(snapshot.simulators.count)", Chrome.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Kept on purpose")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                    ForEach(snapshot.protectedKeeps) { keep in
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Chrome.muted)
                            Text(keep.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Chrome.text)
                            Spacer()
                            Text(keep.reason)
                                .font(.caption)
                                .foregroundStyle(Chrome.muted)
                        }
                    }
                }
                .padding(16)
                .housekeepingCard()
            }
            .padding(22)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            legendRow(Chrome.leftoversHue, "Leftovers", snapshot.totals.leftoverBytes)
            legendRow(Chrome.mediaHue, "Media", snapshot.totals.mediaBytes)
            legendRow(Chrome.worktreeHue, "Worktrees", snapshot.totals.worktreeBytes)
        }
    }

    private func legendRow(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(Chrome.muted)
            Text(ByteFormat.string(bytes)).font(.caption.weight(.semibold)).foregroundStyle(Chrome.text)
        }
    }

    private func stat(_ title: String, _ value: String, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Chrome.muted)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(hue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .housekeepingCard()
    }
}
