import SwiftUI
#if os(macOS)
import AVKit
#endif

struct MediaModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    private var selected: MediaEvidence? {
        snapshot.media.first(where: { $0.id == model.selectedMediaID }) ?? snapshot.media.first
    }

    var body: some View {
        if snapshot.media.isEmpty {
            EmptyStateView(
                title: "No Desktop evidence",
                detail: "Prove and evidence images and videos on the Desktop show up here after a scan."
            )
        } else {
            HStack(spacing: 0) {
                gallery
                Divider().background(Color.white.opacity(0.06))
                if let media = selected {
                    inspector(media)
                }
            }
            .onAppear {
                if model.selectedMediaID == nil {
                    model.selectedMediaID = snapshot.media.first?.id
                }
            }
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                ForEach(snapshot.media) { item in
                    Button {
                        model.selectedMediaID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            MediaThumb(item: item, selected: model.selectedMediaID == item.id)
                            Text(item.filename)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Chrome.text)
                                .lineLimit(1)
                            HStack {
                                Text(ByteFormat.string(item.bytes))
                                    .font(.caption2)
                                    .foregroundStyle(Chrome.muted)
                                Spacer()
                                UsageBadge(usage: item.usage)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func inspector(_ item: MediaEvidence) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.filename)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Chrome.text)
                MediaPreviewStage(item: item)
                    .frame(height: 240)
                if let pr = item.pullRequest {
                    Text("Already used on \(pr)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Chrome.mediaHue)
                }
                Text(item.caption)
                    .font(.callout)
                    .foregroundStyle(Chrome.muted)
                Text(item.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Chrome.faint)
                    .textSelection(.enabled)
                ValidationPanel(
                    usage: item.usage,
                    usageReason: item.usageReason,
                    lastAccess: item.lastAccessAt,
                    lastAccessSource: item.lastAccessSource,
                    handles: item.holder.map { [OpenHandle(pid: $0.pid, process: $0.name, fd: nil, mode: "r")] } ?? [],
                    parent: item.holder.map { "\($0.name) · parent \($0.parentName)" },
                    extra: "Already-used PR evidence is a cleanup candidate. This app does not delete it."
                )
            }
            .padding(20)
            .frame(width: 360, alignment: .leading)
        }
    }
}

struct MediaThumb: View {
    var item: MediaEvidence
    var selected: Bool

    var body: some View {
        ZStack {
            MediaPreviewStage(item: item)
            if item.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 6)
            }
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Chrome.mediaHue : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
    }
}

struct MediaPreviewStage: View {
    var item: MediaEvidence

    var body: some View {
        #if os(macOS)
        if FileManager.default.fileExists(atPath: item.path) {
            if item.kind == .image, let nsImage = NSImage(contentsOfFile: item.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else if item.kind == .video {
                VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: item.path)))
            } else {
                mockArt
            }
        } else {
            mockArt
        }
        #else
        mockArt
        #endif
    }

    private var mockArt: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: item.kind == .video
                    ? [Color(red: 0.22, green: 0.10, blue: 0.36), Color(red: 0.08, green: 0.12, blue: 0.28)]
                    : [Color(red: 0.16, green: 0.18, blue: 0.32), Color(red: 0.08, green: 0.22, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind == .video ? "VIDEO" : "IMAGE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(item.filename)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(10)
        }
    }
}
