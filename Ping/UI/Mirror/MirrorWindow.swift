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
        let defaults = UserDefaults.standard
        if let dict = defaults.dictionary(forKey: positionKey),
           let x = dict["x"] as? CGFloat,
           let y = dict["y"] as? CGFloat {
            return NSPoint(x: x, y: y)
        }

        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        return NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
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
}
