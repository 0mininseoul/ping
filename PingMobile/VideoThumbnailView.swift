import SwiftUI
import AVFoundation
import PingKit

enum PingMobileError: Error { case notPaired }

/// Downloads a message's 3-second clip once and caches it on disk. The thumbnail
/// and the fullscreen player both read the same cached file, so a tapped video
/// plays instantly after its thumbnail has loaded.
actor VideoCache {
    static let shared = VideoCache()
    private var inflight: [String: Task<URL, Error>] = [:]

    nonisolated func cachedURL(for message: VideoMessage) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-clip-\(message.videoId).mp4")
    }

    func localURL(for message: VideoMessage) async throws -> URL {
        let url = cachedURL(for: message)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        if let existing = inflight[message.videoId] { return try await existing.value }

        let task = Task<URL, Error> {
            guard let client = await AppEnvironment.shared.makeClient() else {
                throw PingMobileError.notPaired
            }
            let data = try await client.downloadVideo(message)
            try data.write(to: url, options: .atomic)
            return url
        }
        inflight[message.videoId] = task
        defer { inflight[message.videoId] = nil }
        return try await task.value
    }
}

/// Shows the first frame of a received ping as its thumbnail (mirrors the macOS
/// history view, which extracts a frame at 0.5s rather than storing a poster).
struct VideoThumbnailView: View {
    let message: VideoMessage

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
                if failed {
                    Image(systemName: "play.slash.fill").foregroundStyle(.secondary)
                } else {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .overlay {
            if image != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 4)
            }
        }
        .task(id: message.id) { await load() }
    }

    private func load() async {
        guard let url = try? await VideoCache.shared.localURL(for: message) else {
            failed = true
            return
        }
        if let frame = await Self.extractFrame(url) {
            image = frame
        } else {
            failed = true
        }
    }

    static func extractFrame(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            if #available(iOS 16.0, *) {
                let cg = try await generator.image(at: time).image
                return UIImage(cgImage: cg)
            } else {
                let cg = try generator.copyCGImage(at: time, actualTime: nil)
                return UIImage(cgImage: cg)
            }
        } catch {
            return nil
        }
    }
}
