import SwiftUI

struct TabChrome: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HousekeepingModule.allCases) { item in
                Button {
                    model.show(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                        Text(item.title)
                    }
                    .font(.subheadline.weight(model.module == item ? .semibold : .regular))
                    .foregroundStyle(model.module == item ? Chrome.text : Chrome.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(model.module == item ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NotchCompanion: View {
    var snapshot: Snapshot?

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(snapshot?.source == .macos ? Chrome.accent : Chrome.amber)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Chrome.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .help("Compact companion. Tabs live in the dashboard, not here.")
    }

    private var label: String {
        guard let snapshot else { return "Scan idle" }
        if snapshot.source == .mock {
            return "Mock · companion"
        }
        return "Live · companion"
    }
}
