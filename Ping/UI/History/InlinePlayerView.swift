import SwiftUI
import AVKit

struct InlinePlayerView: View {
    let message: VideoMessage
    let cacheService: HistoryCacheService

    @State private var localURL: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let localURL {
                PlayerBox(
                    url: localURL,
                    aspectRatio: message.aspectRatio ?? 1,
                    isCircle: message.captureMode == .faceOnly
                )
            } else if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            } else {
                ProgressView()
                    .frame(width: 120, height: 120)
            }
        }
        .frame(maxWidth: message.captureMode == .faceOnly ? 180 : 360)
        .task { await load() }
    }

    private func load() async {
        guard let id = message.id else { return }
        if let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) {
            localURL = cached
            return
        }
        do {
            let storage = StorageService()
            let tempURL = try await storage.downloadVideo(remotePath: message.videoUrl)
            localURL = try cacheService.storeDownload(roomId: message.roomId, messageId: id, sourceTemp: tempURL)
        } catch let err {
            error = err.localizedDescription
        }
    }

    struct PlayerBox: NSViewRepresentable {
        let url: URL
        let aspectRatio: Double
        let isCircle: Bool

        func makeNSView(context: Context) -> NSView {
            let container = NSView()
            container.wantsLayer = true
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            container.layer?.addSublayer(layer)
            context.coordinator.player = player
            player.play()
            return container
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if let layer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
                layer.frame = nsView.bounds
                let mask = CAShapeLayer()
                if isCircle {
                    let dim = min(nsView.bounds.width, nsView.bounds.height)
                    let rect = CGRect(
                        x: (nsView.bounds.width - dim) / 2,
                        y: (nsView.bounds.height - dim) / 2,
                        width: dim,
                        height: dim
                    )
                    mask.path = CGPath(ellipseIn: rect, transform: nil)
                } else {
                    mask.path = CGPath(
                        roundedRect: nsView.bounds,
                        cornerWidth: 12,
                        cornerHeight: 12,
                        transform: nil
                    )
                }
                nsView.layer?.mask = mask
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        final class Coordinator {
            var player: AVPlayer?
        }
    }
}
