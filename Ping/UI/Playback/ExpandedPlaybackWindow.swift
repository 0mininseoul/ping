import AppKit
import SwiftUI
import AVKit

@MainActor
final class ExpandedPlaybackWindow: NSWindow {
    private let onDismiss: @MainActor @Sendable () -> Void
    private let player: AVPlayer
    private var keyMonitor: Any?

    init(player: AVPlayer, aspectRatio: Double, on screen: NSScreen, onDismiss: @escaping @MainActor @Sendable () -> Void) {
        self.player = player
        self.onDismiss = onDismiss

        let frameRect = screen.visibleFrame
        let shortSide = min(frameRect.width, frameRect.height) * 0.8
        let size: NSSize
        if aspectRatio >= 1 {
            size = NSSize(width: shortSide * aspectRatio, height: shortSide)
        } else {
            size = NSSize(width: shortSide, height: shortSide / aspectRatio)
        }
        let origin = NSPoint(
            x: frameRect.midX - size.width / 2,
            y: frameRect.midY - size.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let root = ZStack {
            AVPlayerViewRepresentable(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.30), lineWidth: 1)
        }
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
    }

    func present() {
        makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            switch event.keyCode {
            case 49: // Space
                self.dismiss()
                return nil
            case 53: // Esc
                self.dismiss()
                return nil
            case 36: // Enter
                self.player.seek(to: .zero)
                self.player.play()
                return nil
            default:
                return event
            }
        }
    }

    private func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        orderOut(nil)
        onDismiss()
    }
}

struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
            layer.frame = nsView.bounds
        }
    }
}
