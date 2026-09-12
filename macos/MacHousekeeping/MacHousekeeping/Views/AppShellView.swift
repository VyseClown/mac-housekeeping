import SwiftUI

struct AppShellView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Divider().background(Color.white.opacity(0.06))
            VStack(spacing: 0) {
                topBar
                if let banner = model.banner {
                    Text(banner)
                        .font(.caption)
                        .foregroundStyle(Chrome.amber)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Chrome.amber.opacity(0.08))
                }
                content
            }
            .background(Chrome.background)
        }
        .sheet(item: $model.pendingConfirm) { intent in
            ConfirmSheet(model: model, intent: intent)
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.module.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                if let snapshot = model.snapshot {
                    Text("\(snapshot.host.user) · \(snapshot.host.hostname)")
                        .font(.caption)
                        .foregroundStyle(Chrome.muted)
                }
            }
            Spacer()
            Button("Scan leftovers") { model.scan() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let message):
            FailedStateView(message: message, retry: model.scan)
        case .ready(let snapshot):
            switch model.module {
            case .overview:
                OverviewDashboard(model: model, snapshot: snapshot)
            case .leftovers:
                CleanupModuleView(model: model, snapshot: snapshot)
            case .media:
                MediaModuleView(model: model, snapshot: snapshot)
            case .worktrees:
                WorktreeModuleView(model: model, snapshot: snapshot)
            case .processes:
                ProcessModuleView(model: model, snapshot: snapshot)
            }
        }
    }
}

struct ConfirmSheet: View {
    @ObservedObject var model: AppModel
    var intent: DestructiveIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(Chrome.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing deletes, kills, or shuts down from this dialog. Review only.")
                .font(.caption)
                .foregroundStyle(Chrome.amber)
            HStack {
                Button("Cancel") { model.cancelConfirm() }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("I understand") { model.confirmPending() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Chrome.card)
    }

    private var title: String {
        switch intent {
        case .deleteLeftover: return "Delete this leftover?"
        case .killProcess: return "Localize, then kill?"
        }
    }

    private var detail: String {
        guard let snapshot = model.snapshot else { return "Scan first." }
        switch intent {
        case .deleteLeftover(let id):
            let path = snapshot.leftovers.first(where: { $0.id == id })?.path ?? id
            return "\(path) is idle and not nightshift or ai-memory. Nothing deletes until you confirm on a later pass."
        case .killProcess(let pid):
            let name = snapshot.processes.first(where: { $0.pid == pid })?.name ?? "process"
            return "\(name) (\(pid)) can be localized now. This app will not send a signal."
        }
    }
}
