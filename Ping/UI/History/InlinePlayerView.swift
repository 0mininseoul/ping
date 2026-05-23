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
            } else if let error {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 120, height: 60)
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
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { note in
                NSLog("PlayerBox failedToPlayToEnd: \(note.userInfo ?? [:]) url=\(url)")
            }

            player.play()
            return container
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                guard let playerLayer = nsView.layer?.sublayers?.first as? AVPlayerLayer else { return }
                playerLayer.frame = nsView.bounds
                let mask = CAShapeLayer()
                if self.isCircle {
                    let dim = min(nsView.bounds.width, nsView.bounds.height)
                    mask.path = CGPath(ellipseIn: CGRect(x: (nsView.bounds.width - dim) / 2, y: (nsView.bounds.height - dim) / 2, width: dim, height: dim), transform: nil)
                } else {
                    mask.path = CGPath(roundedRect: nsView.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
                }
                nsView.layer?.mask = mask
            }
        }

        func makeCoordinator() -> Coord { Coord() }

        final class Coord {
            var statusObserver: NSKeyValueObservation?
            var endObserver: Any?
            deinit {
                statusObserver?.invalidate()
                if let o = endObserver { NotificationCenter.default.removeObserver(o) }
            }
        }
    }
}
