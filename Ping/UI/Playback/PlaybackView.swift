import SwiftUI
import AVKit

struct PlaybackView: NSViewRepresentable {
    let url: URL
    let onFinish: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.configure(url: url, onFinish: onFinish)
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {}

    final class PlayerNSView: NSView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(url: URL, onFinish: @escaping @MainActor @Sendable () -> Void) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer?.addSublayer(layer)
            self.playerLayer = layer

            let finish = onFinish
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    finish()
                }
            }

            player.play()
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }

        private func setup() {
            wantsLayer = true
            layer = CALayer()
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
