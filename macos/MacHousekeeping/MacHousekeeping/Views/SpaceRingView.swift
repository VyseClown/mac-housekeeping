import SwiftUI

struct SpaceRingView: View {
    var idle: Int64
    var held: Int64
    var idleColor: Color = Chrome.leftoversHue
    var heldColor: Color = Chrome.amber
    var caption: String

    private var total: Double {
        Double(max(idle + held, 1))
    }

    var body: some View {
        let idleSlice = Double(idle) / total
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 22)
            Circle()
                .trim(from: 0, to: idleSlice)
                .stroke(idleColor, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: idleSlice, to: 1)
                .stroke(heldColor, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Text("This tab")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Chrome.muted)
                Text(ByteFormat.string(idle + held))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Chrome.text)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Chrome.faint)
            }
        }
        .frame(width: 220, height: 220)
    }
}
