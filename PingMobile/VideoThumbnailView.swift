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

/// Generates and caches ping thumbnails. A thumbnail is the first frame of the
/// clip (there is no server-stored poster), so the first time we see a video we
/// download it and extract a frame. Results are cached in memory **and on disk**
/// (keyed by video id) so re-renders and later visits are instant. Prefetch runs
/// newest-first with limited concurrency so the most recent pings appear first.
@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    private var queued: Set<String> = []
    private let diskDir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDir = base.appendingPathComponent("ping-thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    /// Warm thumbnails newest-first; already-loaded ids are skipped.
    func prefetch(_ messages: [VideoMessage]) {
        let ordered = messages
            .filter { images[$0.videoId] == nil && !queued.contains($0.videoId) }
            .sorted { $0.createdAt > $1.createdAt }
        guard !ordered.isEmpty else { return }
        ordered.forEach { queued.insert($0.videoId) }
        Task { await run(ordered) }
    }

    private func run(_ ordered: [VideoMessage]) async {
        let dir = diskDir
        var index = 0
        let batchSize = 3
        while index < ordered.count {
            let slice = Array(ordered[index..<min(index + batchSize, ordered.count)])
            await withTaskGroup(of: (String, Data?).self) { group in
                for message in slice {
                    group.addTask { (message.videoId, await ThumbnailStore.produce(message, dir: dir)) }
                }
                for await (id, data) in group {
                    queued.remove(id)
                    if let data, let image = UIImage(data: data) { images[id] = image }
                }
            }
            index += batchSize
        }
    }

    /// Off the main actor: disk cache → download clip → extract frame → JPEG.
    /// Returns JPEG bytes (Sendable) so no UIImage crosses the actor boundary.
    private nonisolated static func produce(_ message: VideoMessage, dir: URL) async -> Data? {
        let disk = dir.appendingPathComponent("\(message.videoId).jpg")
        if let cached = try? Data(contentsOf: disk), !cached.isEmpty { return cached }

        guard let clip = try? await VideoCache.shared.localURL(for: message),
              let frame = await extractFrame(clip),
              let jpeg = frame.jpegData(compressionQuality: 0.8) else { return nil }
        try? jpeg.write(to: disk, options: .atomic)
        return jpeg
    }

    private nonisolated static func extractFrame(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        // Accept any nearby frame instead of an exact seek — much faster.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
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

/// Displays a ping's cached thumbnail (from `ThumbnailStore`) with a play badge.
struct VideoThumbnailView: View {
    @ObservedObject var store: ThumbnailStore
    let message: VideoMessage

    var body: some View {
        ZStack {
            if let image = store.images[message.videoId] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
                ProgressView().scaleEffect(0.7)
            }
        }
        .overlay {
            if store.images[message.videoId] != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 4)
            }
        }
    }
}
