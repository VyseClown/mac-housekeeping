import SwiftUI
#if os(macOS)
import AppKit
import AVKit
#endif

struct MediaModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.media.isEmpty {
                    EmptyStateView(
                        title: "No Desktop evidence",
                        detail: "Prove and evidence images and videos on the Desktop show up here after a scan."
                    )
                } else {
                    gallery
                }
            }
            .navigationTitle("Media")
            .navigationDestination(item: $model.selectedMediaID) { id in
                if let item = snapshot.media.first(where: { $0.id == id }) {
                    inspector(item)
                }
            }
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                ForEach(snapshot.media) { item in
                    Button {
                        model.selectedMediaID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            MediaThumb(item: item, selected: false)
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
            .padding(22)
        }
    }

    private func inspector(_ item: MediaEvidence) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("← Back") { model.selectedMediaID = nil }
                    .buttonStyle(QuietButtonStyle())
                MediaPreviewStage(item: item)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(item.filename)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Chrome.text)
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
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Preview")
    }
}

struct MediaThumb: View {
    var item: MediaEvidence
    var selected: Bool

    var body: some View {
        ZStack {
            if item.kind == .image,
               FileManager.default.fileExists(atPath: item.path),
               let nsImage = NSImage(contentsOfFile: item.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: item.kind == .video
                        ? [Color(red: 0.22, green: 0.10, blue: 0.36), Color(red: 0.08, green: 0.12, blue: 0.28)]
                        : [Color(red: 0.16, green: 0.18, blue: 0.32), Color(red: 0.08, green: 0.22, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            if item.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 6)
            }
        }
        .frame(height: 120)
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
