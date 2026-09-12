import SwiftUI

struct SpaceRingView: View {
    var leftovers: Int64
    var media: Int64
    var worktrees: Int64

    private var total: Double {
        Double(max(leftovers + media + worktrees, 1))
    }

    var body: some View {
        let leftoverSlice = Double(leftovers) / total
        let mediaSlice = Double(media) / total
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 22)
            Circle()
                .trim(from: 0, to: leftoverSlice)
                .stroke(Chrome.leftoversHue, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: leftoverSlice, to: leftoverSlice + mediaSlice)
                .stroke(Chrome.mediaHue, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: leftoverSlice + mediaSlice, to: 1)
                .stroke(Chrome.worktreeHue, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Text("Mapped")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Chrome.muted)
                Text(ByteFormat.string(leftovers + media + worktrees))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Chrome.text)
                Text("on Alessandro's Mac")
                    .font(.caption)
                    .foregroundStyle(Chrome.faint)
            }
        }
        .frame(width: 268, height: 268)
        .shadow(color: Chrome.accent.opacity(0.12), radius: 30)
    }
}
