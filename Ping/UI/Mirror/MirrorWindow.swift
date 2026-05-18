import AppKit
import SwiftUI

@MainActor
final class MirrorWindow: NSWindow {
    static let size = NSSize(width: 200, height: 200)
    private static let positionKey = "ping.mirror.lastPosition"

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init<Content: View>(rootView: Content) {
        let initialRect = NSRect(origin: Self.loadLastPosition(), size: Self.size)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: AnyView(rootView))
        host.frame = NSRect(origin: .zero, size: Self.size)
        contentView = host
    }

    static func loadLastPosition() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }

        return WindowPositioning.visibleOrigin(
            preferred: savedPosition(),
            windowSize: size,
            in: screen.visibleFrame
        )
    }

    func ensureVisibleOnCurrentScreen() {
        guard let screen = screenForCurrentFrame() ?? NSScreen.main else { return }
        let origin = WindowPositioning.visibleOrigin(
            preferred: frame.origin,
            windowSize: frame.size,
            in: screen.visibleFrame
        )
        setFrameOrigin(origin)
    }

    func savePosition() {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y],
            forKey: Self.positionKey
        )
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        savePosition()
    }

    private static func savedPosition() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard let dict = defaults.dictionary(forKey: positionKey),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat else {
            return nil
        }

        return NSPoint(x: x, y: y)
    }

    private func screenForCurrentFrame() -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.intersects(frame)
        }
    }
}
