import SwiftUI

struct TabChrome: View {
    var module: HousekeepingModule
    var onSelect: (HousekeepingModule) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HousekeepingModule.allCases) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                        Text(item.title)
                    }
                    .font(.subheadline.weight(module == item ? .semibold : .regular))
                    .foregroundStyle(module == item ? Chrome.text : Chrome.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(module == item ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NotchCompanion: View {
    var snapshot: Snapshot?
    var scanning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(dotColor)
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

    private var dotColor: Color {
        if scanning { return Chrome.amber }
        return snapshot?.source == .macos ? Chrome.accent : Chrome.amber
    }

    private var label: String {
        if scanning {
            return snapshot == nil ? "Scanning" : "Scanning · companion"
        }
        guard let snapshot else { return "Scan idle" }
        if snapshot.source == .mock {
            return "Mock · companion"
        }
        return "Live · companion"
    }
}
