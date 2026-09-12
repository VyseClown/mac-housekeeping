import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Chrome.accent.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(Chrome.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Housekeeping")
                        .font(.headline)
                        .foregroundStyle(Chrome.text)
                    Text("Alessandro Gentil")
                        .font(.caption)
                        .foregroundStyle(Chrome.muted)
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 4) {
                ForEach(HousekeepingModule.allCases) { item in
                    Button {
                        model.module = item
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .frame(width: 18)
                            Text(item.title)
                                .font(.subheadline.weight(model.module == item ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(model.module == item ? Chrome.text : Chrome.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(model.module == item ? Color.white.opacity(0.07) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.source == .mock ? "Mock Mac data" : "Live Mac scan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(snapshot.source == .mock ? Chrome.amber : Chrome.accent)
                    Text(snapshot.host.os)
                        .font(.caption2)
                        .foregroundStyle(Chrome.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .frame(width: 232)
        .background(Chrome.sidebar)
    }
}
