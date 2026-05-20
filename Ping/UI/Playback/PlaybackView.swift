import SwiftUI
import AVKit

struct PlaybackView: NSViewRepresentable {
    let url: URL
    let onFirstPlayEnd: @MainActor @Sendable () -> Void
    let controllerBox: ControllerBox

    final class ControllerBox {
        var player: AVPlayer?
        func replay() {
            player?.seek(to: .zero)
            player?.play()
        }
    }

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.configure(url: url, onFirstEnd: onFirstPlayEnd, controllerBox: controllerBox)
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {}

    final class PlayerNSView: NSView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        nonisolated(unsafe) private var observer: NSObjectProtocol?
        nonisolated(unsafe) private var didFirePlayEnd = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(
            url: URL,
            onFirstEnd: @escaping @MainActor @Sendable () -> Void,
            controllerBox: ControllerBox
        ) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            controllerBox.player = player

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer?.addSublayer(layer)
            self.playerLayer = layer

            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self, weak player] _ in
                player?.pause()
                guard let self, !self.didFirePlayEnd else { return }
                self.didFirePlayEnd = true
                Task { @MainActor in onFirstEnd() }
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
