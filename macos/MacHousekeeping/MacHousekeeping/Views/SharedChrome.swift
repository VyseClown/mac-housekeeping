import SwiftUI

struct EmptyStateView: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Chrome.accent)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Chrome.text)
            Text(detail)
                .font(.callout)
                .foregroundStyle(Chrome.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning leftovers, media, and worktrees")
                .font(.callout)
                .foregroundStyle(Chrome.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailedStateView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Chrome.amber)
            Text("Scan failed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Chrome.text)
            Text(message)
                .font(.callout)
                .foregroundStyle(Chrome.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Scan again", action: retry)
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .foregroundStyle(Color.black.opacity(0.86))
            .background(
                LinearGradient(
                    colors: [Chrome.accent, Chrome.accentDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(Chrome.text)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct CategoryCard: View {
    var title: String
    var size: String
    var detail: String
    var symbol: String
    var hue: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(hue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Chrome.faint)
                }
                Text(size)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Chrome.text)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Chrome.muted)
                        .lineLimit(2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .housekeepingCard()
        }
        .buttonStyle(.plain)
    }
}
