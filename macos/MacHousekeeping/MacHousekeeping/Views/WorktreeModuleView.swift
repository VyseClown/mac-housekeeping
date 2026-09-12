import SwiftUI

struct WorktreeModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot
    @State private var showBranches = false

    private var worktrees: [GitWorkspace] {
        snapshot.workspaces.filter { $0.kind == .worktree }
    }

    private var branches: [GitWorkspace] {
        snapshot.workspaces.filter { $0.kind == .localBranch }
    }

    private var barWorktrees: [GitWorkspace] {
        Array(worktrees.prefix(8))
    }

    private var totalWorktreeBytes: Int64 {
        worktrees.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.workspaces.isEmpty {
                    EmptyStateView(
                        title: model.pendingModules.contains(.worktrees)
                            ? "Scanning branches"
                            : "No worktrees mapped",
                        detail: model.pendingModules.contains(.worktrees)
                            ? "Porcelain list lands first. /tmp sizes fill in behind it."
                            : "Local branches and git worktrees, including large /tmp leftovers, show here. This app never runs git worktree remove."
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Branches and worktrees")
            .navigationDestination(item: $model.focus.workspaceID) { id in
                if let item = snapshot.workspaces.first(where: { $0.id == id }) {
                    detail(item)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Worktree space")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                Text("\(ByteFormat.string(totalWorktreeBytes)) across \(worktrees.count) worktrees. Leftovers and media stay on their tabs.")
                    .font(.callout)
                    .foregroundStyle(Chrome.muted)
                stackedBar
                if worktrees.count > barWorktrees.count {
                    Text("\(worktrees.count - barWorktrees.count) more leftover trees stay in the list.")
                        .font(.caption)
                        .foregroundStyle(Chrome.faint)
                }
                sectionTitle("Worktrees")
                ForEach(worktrees) { item in
                    WorkspaceRow(item: item) {
                        model.focus.workspaceID = item.id
                    }
                }
                Button {
                    showBranches.toggle()
                } label: {
                    HStack {
                        sectionTitle("Local branches")
                        Spacer()
                        Text(showBranches ? "Hide" : "\(branches.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Chrome.muted)
                    }
                }
                .buttonStyle(.plain)
                if showBranches {
                    ForEach(branches) { item in
                        WorkspaceRow(item: item) {
                            model.focus.workspaceID = item.id
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(barWorktrees) { item in
                    let width = max(8, geo.size.width * CGFloat(item.bytes) / CGFloat(max(totalWorktreeBytes, 1)))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.usage == .inUse ? Chrome.amber : Chrome.worktreeHue)
                        .frame(width: width)
                        .onTapGesture { model.focus.workspaceID = item.id }
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

    private func detail(_ item: GitWorkspace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("← Back") { model.focus.workspaceID = nil }
                    .buttonStyle(QuietButtonStyle())
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                Text(item.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Chrome.muted)
                    .textSelection(.enabled)
                ValidationPanel(
                    usage: item.usage,
                    usageReason: item.usageReason,
                    lastAccess: item.lastAccessAt,
                    lastAccessSource: item.lastAccessAt == nil ? nil : "stat",
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
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Worktree")
    }
}

struct WorkspaceRow: View, Equatable {
    var item: GitWorkspace
    var action: () -> Void

    static func == (lhs: WorkspaceRow, rhs: WorkspaceRow) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        Button(action: action) {
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
                Image(systemName: "chevron.right")
                    .foregroundStyle(Chrome.faint)
            }
            .padding(12)
            .housekeepingCard()
        }
        .buttonStyle(.plain)
    }
}
