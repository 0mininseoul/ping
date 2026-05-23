import SwiftUI
import AVKit

final class InlinePlayerController: ObservableObject {
    @Published var isPaused: Bool = false
    weak var player: AVPlayer?

    func replay() {
        player?.seek(to: .zero)
        player?.play()
        isPaused = false
    }
}

struct InlinePlayerView: View {
    let message: VideoMessage
    let isMine: Bool
    let archivePeerName: String
    let cacheService: HistoryCacheService
    @ObservedObject var controller: InlinePlayerController

    @State private var localURL: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let localURL {
                PlayerBox(
                    url: localURL,
                    aspectRatio: message.aspectRatio ?? 1,
                    isCircle: message.captureMode == .faceOnly,
                    controller: controller
                )
                .frame(width: playerSize.width, height: playerSize.height)
            } else if let error {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: playerSize.width, height: playerSize.height)
            } else {
                ProgressView()
                    .frame(width: playerSize.width, height: playerSize.height)
            }
        }
        .task { await load() }
    }

    private var playerSize: CGSize {
        if message.captureMode == .faceOnly {
            return CGSize(width: 128, height: 128)
        }

        let width: CGFloat = 280
        let aspectRatio = CGFloat(max(0.5, min(3.0, message.aspectRatio ?? 1.78)))
        return CGSize(width: width, height: width / aspectRatio)
    }

    private func load() async {
        guard let id = message.id else { return }
        if let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) {
            localURL = cached
            return
        }
        if let archived = archivedVideoURL() {
            localURL = archived
            return
        }
        do {
            let storage = StorageService()
            let tempURL = try await storage.downloadVideo(remotePath: message.videoUrl)
            localURL = try cacheService.storeDownload(roomId: message.roomId, messageId: id, sourceTemp: tempURL)
        } catch let err {
            let desc = err.localizedDescription
            if desc.contains("Object not found") || desc.contains("404") || desc.contains("not found") {
                error = "영상이 만료되어 더 이상 재생할 수 없어요."
            } else {
                error = "영상 로드 실패: \(desc)"
            }
            NSLog("InlinePlayerView load failed: \(err) — message=\(id) videoUrl=\(message.videoUrl)")
        }
    }

    private func archivedVideoURL() -> URL? {
        guard let createdAt = message.createdAt else { return nil }
        let direction: LocalArchive.Direction = isMine ? .sent : .received
        return LocalArchive.existingVideoURL(
            direction: direction,
            nickname: archivePeerName,
            date: createdAt
        )
    }

    struct PlayerBox: NSViewRepresentable {
        let url: URL
        let aspectRatio: Double
        let isCircle: Bool
        @ObservedObject var controller: InlinePlayerController

        func makeNSView(context: Context) -> NSView {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            container.wantsLayer = true
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            // frame을 즉시 설정 (zero frame guard)
            playerLayer.frame = container.bounds
            container.layer?.addSublayer(playerLayer)
            controller.player = player

            // KVO: AVPlayerItem status 변화 logging
            context.coordinator.statusObserver = item.observe(\.status, options: [.new]) { item, _ in
                NSLog("PlayerBox status=\(item.status.rawValue) error=\(String(describing: item.error)) url=\(url)")
            }

            // 재생 실패 logging
            context.coordinator.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.pause()
                Task { @MainActor in controller.isPaused = true }
            }
            context.coordinator.failureObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { note in
                NSLog("PlayerBox failedToPlayToEnd: \(note.userInfo ?? [:]) url=\(url)")
            }

            applyLayerLayout(in: container, context: context)
            return container
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            applyLayerLayout(in: nsView, context: context)
            startPlaybackIfReady(in: nsView, context: context)
        }

        private func startPlaybackIfReady(in nsView: NSView, context: Context) {
            let bounds = nsView.bounds
            guard bounds.width > 8, bounds.height > 8 else { return }
            guard !context.coordinator.didStartPlayback else { return }
            guard let playerLayer = nsView.layer?.sublayers?.first as? AVPlayerLayer,
                  let player = playerLayer.player else { return }

            context.coordinator.didStartPlayback = true
            controller.isPaused = false
            player.seek(to: .zero)
            player.play()
        }

        private func applyLayerLayout(in nsView: NSView, context: Context) {
            let bounds = nsView.bounds
            guard context.coordinator.lastBounds != bounds || context.coordinator.lastIsCircle != isCircle else { return }
            guard let playerLayer = nsView.layer?.sublayers?.first as? AVPlayerLayer else { return }

            playerLayer.frame = bounds
            let mask = CAShapeLayer()
            if isCircle {
                let dim = min(bounds.width, bounds.height)
                mask.path = CGPath(
                    ellipseIn: CGRect(
                        x: (bounds.width - dim) / 2,
                        y: (bounds.height - dim) / 2,
                        width: dim,
                        height: dim
                    ),
                    transform: nil
                )
            } else {
                mask.path = CGPath(roundedRect: bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
            }
            nsView.layer?.mask = mask
            context.coordinator.lastBounds = bounds
            context.coordinator.lastIsCircle = isCircle
        }

        func makeCoordinator() -> Coord { Coord() }

        final class Coord {
            var statusObserver: NSKeyValueObservation?
            var endObserver: Any?
            var failureObserver: Any?
            var lastBounds: CGRect = .null
            var lastIsCircle: Bool?
            var didStartPlayback = false
            deinit {
                statusObserver?.invalidate()
                if let o = endObserver { NotificationCenter.default.removeObserver(o) }
                if let o = failureObserver { NotificationCenter.default.removeObserver(o) }
            }
        }
    }
}
