import SwiftUI

struct ValidationPanel: View {
    var usage: UsageState
    var usageReason: String
    var lastAccess: Date?
    var lastAccessSource: String?
    var handles: [OpenHandle]
    var parent: String?
    var extra: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usage validation")
                    .font(.headline)
                    .foregroundStyle(Chrome.text)
                Spacer()
                UsageBadge(usage: usage)
            }
            row("Open handles", handles.isEmpty ? "None" : handles.map { "\($0.process) (\($0.pid) fd \($0.fd ?? "-"))" }.joined(separator: " · "))
            if let lastAccess, let lastAccessSource {
                row("Last access", "\(RelativeDate.string(from: lastAccess)) · \(lastAccessSource)")
            }
            row("Parent / holder", parent ?? "No holder — nothing to walk")
            row("Idle vs in use", usageReason)
            if let extra {
                Text(extra)
                    .font(.caption)
                    .foregroundStyle(Chrome.muted)
            }
        }
        .padding(16)
        .housekeepingCard()
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Chrome.faint)
            Text(value).font(.callout).foregroundStyle(Chrome.text).textSelection(.enabled)
        }
    }
}
