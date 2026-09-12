import SwiftUI
#if os(macOS)
import AppKit
import AVFoundation
import ImageIO
#endif

struct MediaModuleView: View {
    @ObservedObject var model: AppModel
    var snapshot: Snapshot

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.media.isEmpty {
                    EmptyStateView(
                        title: model.pendingModules.contains(.media)
                            ? "Scanning Desktop media"
                            : "No Desktop evidence",
                        detail: model.pendingModules.contains(.media)
                            ? "This tab paints when the Desktop walk finishes. Video cells stay gradients."
                            : "Prove and evidence images and videos on the Desktop show up here after a scan."
                    )
                } else {
                    gallery
                }
            }
            .navigationTitle("Media")
            .navigationDestination(item: $model.focus.mediaID) { id in
                if let item = snapshot.media.first(where: { $0.id == id }) {
                    inspector(item)
                }
            }
        }
    }

    private var gallery: some View {
        ScrollView {
            if let note = snapshot.warnings.first(where: { $0.contains("largest") && $0.contains("Desktop leftover") }) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Chrome.muted)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                ForEach(snapshot.media) { item in
                    Button {
                        model.focus.mediaID = item.id
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
                Button("← Back") { model.focus.mediaID = nil }
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

struct MediaThumb: View, Equatable {
    var item: MediaEvidence
    var selected: Bool

    static func == (lhs: MediaThumb, rhs: MediaThumb) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.path == rhs.item.path
            && lhs.item.kind == rhs.item.kind
            && lhs.selected == rhs.selected
    }

    var body: some View {
        ZStack {
            if item.kind == .video {
                mediaGradient(video: true)
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 6)
            } else {
                AsyncMediaImage(path: item.path, kind: .image, pixelCap: 360)
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

struct MediaPreviewStage: View, Equatable {
    var item: MediaEvidence

    static func == (lhs: MediaPreviewStage, rhs: MediaPreviewStage) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.path == rhs.item.path && lhs.item.kind == rhs.item.kind
    }

    var body: some View {
        ZStack {
            AsyncMediaImage(path: item.path, kind: item.kind, pixelCap: 640)
            if item.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 8)
            }
        }
    }
}

struct AsyncMediaImage: View {
    var path: String
    var kind: MediaKind
    var pixelCap: CGFloat
    #if os(macOS)
    @State private var image: NSImage?
    #endif

    var body: some View {
        ZStack {
            mediaGradient(video: kind == .video)
            #if os(macOS)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
            #endif
        }
        #if os(macOS)
        .task(id: "\(path)|\(Int(pixelCap))") {
            image = await ThumbCache.shared.image(at: path, kind: kind, pixelCap: pixelCap)
        }
        #endif
    }
}

func mediaGradient(video: Bool) -> LinearGradient {
    LinearGradient(
        colors: video
            ? [Color(red: 0.22, green: 0.10, blue: 0.36), Color(red: 0.08, green: 0.12, blue: 0.28)]
            : [Color(red: 0.16, green: 0.18, blue: 0.32), Color(red: 0.08, green: 0.22, blue: 0.24)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

#if os(macOS)
enum ThumbCache {
    static let shared = ThumbCacheStore()
}

final class ThumbCacheStore: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 64
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(at path: String, kind: MediaKind, pixelCap: CGFloat) async -> NSImage? {
        await Task.detached(priority: .utility) {
            self.decode(path: path, kind: kind, pixelCap: pixelCap)
        }.value
    }

    private func decode(path: String, kind: MediaKind, pixelCap: CGFloat) -> NSImage? {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(path)|\(mtime)|\(Int(pixelCap))|\(kind.rawValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let decoded: NSImage?
        switch kind {
        case .image:
            decoded = imageIOThumb(path: path, pixelCap: pixelCap)
        case .video:
            decoded = videoPoster(path: path, pixelCap: pixelCap)
        }
        if let decoded {
            let cost = Int((decoded.size.width * decoded.size.height) * 4)
            cache.setObject(decoded, forKey: key, cost: max(cost, 1))
        }
        return decoded
    }

    private func imageIOThumb(path: String, pixelCap: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(pixelCap),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func videoPoster(path: String, pixelCap: CGFloat) -> NSImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelCap, height: pixelCap)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif
