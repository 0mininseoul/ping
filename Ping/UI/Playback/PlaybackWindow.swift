import AppKit
import SwiftUI

@MainActor
final class PlaybackWindow: NSWindow {
    static let size = NSSize(width: 200, height: 200)

    init(videoURL: URL, atScreenPoint origin: NSPoint, onFinish: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: origin, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let root = ZStack {
            PlaybackView(url: videoURL) { [weak self] in
                self?.fadeOutAndClose(onFinish)
            }
            .clipShape(Circle())

            Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)

        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: Self.size)
        contentView = host
        alphaValue = 0
    }

    func fadeIn() {
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            animator().alphaValue = 1.0
        }
    }

    private func fadeOutAndClose(_ done: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.30
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            done()
        })
    }
}
