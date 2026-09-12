import SwiftUI

struct WorktreeModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    private var worktrees: [GitWorkspace] {
        snapshot.workspaces.filter { $0.kind == .worktree }
    }

    private var branches: [GitWorkspace] {
        snapshot.workspaces.filter { $0.kind == .localBranch }
    }

    private var selected: GitWorkspace? {
        snapshot.workspaces.first(where: { $0.id == model.selectedWorkspaceID }) ?? worktrees.first
    }

    private var totalWorktreeBytes: Int64 {
        worktrees.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        if snapshot.workspaces.isEmpty {
            EmptyStateView(
                title: "No worktrees mapped",
                detail: "Local branches and git worktrees, including large /tmp leftovers, show here. This app never runs git worktree remove."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Worktree space")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Chrome.text)
                    Text("\(ByteFormat.string(totalWorktreeBytes)) across \(worktrees.count) worktrees. This map is separate from leftover cards.")
                        .font(.callout)
                        .foregroundStyle(Chrome.muted)
                    stackedBar
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Worktrees")
                            ForEach(worktrees) { item in
                                workspaceRow(item)
                            }
                            sectionTitle("Local branches")
                            ForEach(branches) { item in
                                workspaceRow(item)
                            }
                        }
                        if let item = selected {
                            detail(item)
                                .frame(width: 340)
                        }
                    }
                }
                .padding(22)
            }
            .onAppear {
                if model.selectedWorkspaceID == nil {
                    model.selectedWorkspaceID = worktrees.first?.id
                }
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(worktrees) { item in
                    let width = max(8, geo.size.width * CGFloat(item.bytes) / CGFloat(max(totalWorktreeBytes, 1)))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.usage == .inUse ? Chrome.amber : Chrome.worktreeHue.opacity(item.id == model.selectedWorkspaceID ? 1 : 0.7))
                        .frame(width: width)
                        .onTapGesture { model.selectedWorkspaceID = item.id }
                }
            }
        }
        .frame(height: 28)
        .padding(6)
        .housekeepingCard()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Chrome.text)
            .padding(.top, 8)
    }

    private func workspaceRow(_ item: GitWorkspace) -> some View {
        Button {
            model.selectedWorkspaceID = item.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Chrome.text)
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(Chrome.muted)
                        .lineLimit(1)
                    Text("\(item.repoName) · \(item.repoRoot)")
                        .font(.caption2)
                        .foregroundStyle(Chrome.faint)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.kind == .worktree ? ByteFormat.string(item.bytes) : "shared objects")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Chrome.text)
                    UsageBadge(usage: item.usage)
                }
            }
            .padding(12)
            .background(model.selectedWorkspaceID == item.id ? Color.white.opacity(0.06) : Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ item: GitWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.name)
                .font(.headline)
                .foregroundStyle(Chrome.text)
            ValidationPanel(
                usage: item.usage,
                usageReason: item.usageReason,
                lastAccess: nil,
                lastAccessSource: nil,
                handles: item.holdingProcess.map { [OpenHandle(pid: $0.pid, process: $0.name, fd: nil, mode: nil)] } ?? [],
                parent: item.holdingProcess.map { "\($0.name) · parent \($0.parentName)" },
                extra: "Suggested later only. This app does not run git worktree remove or delete branches."
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("Later suggestion")
                    .font(.caption)
                    .foregroundStyle(Chrome.faint)
                Text(item.suggestedAction.label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Chrome.blue)
                    .textSelection(.enabled)
            }
            .padding(12)
            .housekeepingCard()
        }
    }
}
