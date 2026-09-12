import SwiftUI

enum Chrome {
    static let background = Color(red: 0.055, green: 0.062, blue: 0.075)
    static let sidebar = Color(red: 0.035, green: 0.039, blue: 0.048)
    static let card = Color(red: 0.086, green: 0.094, blue: 0.110)
    static let cardStroke = Color.white.opacity(0.06)
    static let accent = Color(red: 0.23, green: 0.84, blue: 0.52)
    static let accentDeep = Color(red: 0.10, green: 0.55, blue: 0.38)
    static let blue = Color(red: 0.31, green: 0.69, blue: 0.96)
    static let amber = Color(red: 0.96, green: 0.70, blue: 0.24)
    static let rose = Color(red: 0.95, green: 0.38, blue: 0.42)
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.48)
    static let faint = Color.white.opacity(0.28)

    static let leftoversHue = Color(red: 0.23, green: 0.84, blue: 0.52)
    static let mediaHue = Color(red: 0.62, green: 0.48, blue: 0.98)
    static let worktreeHue = Color(red: 0.31, green: 0.69, blue: 0.96)
}

extension View {
    func housekeepingCard() -> some View {
        self
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Chrome.cardStroke, lineWidth: 1)
            )
    }
}

struct UsageBadge: View {
    var usage: UsageState

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
    }

    private var label: String {
        switch usage {
        case .inUse: return "In use"
        case .idle: return "Idle"
        case .recent: return "Recent"
        case .protected: return "Kept"
        }
    }

    private var color: Color {
        switch usage {
        case .inUse: return Chrome.amber
        case .idle: return Chrome.accent
        case .recent: return Chrome.blue
        case .protected: return Chrome.muted
        }
    }
}
