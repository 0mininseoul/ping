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
            let container = PlayerContainerView()
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            container.configure(playerLayer: playerLayer, isCircle: isCircle)
            controller.player = player

            context.coordinator.statusObserver = item.observe(\.status, options: [.new]) { item, _ in
                NSLog("PlayerBox status=\(item.status.rawValue) error=\(String(describing: item.error)) url=\(url)")
            }

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

            return container
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let view = nsView as? PlayerContainerView else { return }
            view.isCircle = isCircle
        }

        final class PlayerContainerView: NSView {
            private(set) var playerLayer: AVPlayerLayer?
            var isCircle = false {
                didSet {
                    guard oldValue != isCircle else { return }
                    lastBounds = .null
                    needsLayout = true
                }
            }
            private var lastBounds: CGRect = .null
            private var didStartPlayback = false

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                setup()
            }

            required init?(coder: NSCoder) {
                super.init(coder: coder)
                setup()
            }

            override func layout() {
                super.layout()
                updateLayerLayout()
                startPlaybackIfReady()
            }

            func configure(playerLayer: AVPlayerLayer, isCircle: Bool) {
                self.playerLayer?.removeFromSuperlayer()
                self.playerLayer = playerLayer
                self.isCircle = isCircle
                layer?.addSublayer(playerLayer)
                needsLayout = true
            }

            private func setup() {
                wantsLayer = true
                layer = CALayer()
            }

            private func updateLayerLayout() {
                let bounds = self.bounds
                guard lastBounds != bounds else { return }
                guard let playerLayer else { return }

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
                layer?.mask = mask
                lastBounds = bounds
            }

            private func startPlaybackIfReady() {
                let bounds = self.bounds
                guard bounds.width > 8, bounds.height > 8 else { return }
                guard !didStartPlayback else { return }
                guard let player = playerLayer?.player else { return }

                didStartPlayback = true
                player.seek(to: .zero)
                player.play()
            }
        }

        func makeCoordinator() -> Coord { Coord() }

        final class Coord {
            var statusObserver: NSKeyValueObservation?
            var endObserver: Any?
            var failureObserver: Any?
            deinit {
                statusObserver?.invalidate()
                if let o = endObserver { NotificationCenter.default.removeObserver(o) }
                if let o = failureObserver { NotificationCenter.default.removeObserver(o) }
            }
        }
    }
}
