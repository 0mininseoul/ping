import AppKit
import SwiftUI

@MainActor
final class MirrorWindow: NSWindow {
    static let faceOnlySize = NSSize(width: 200, height: 200)
    private static let positionKey = "ping.mirror.lastPosition"

    static func sizeForScreenFace(on screen: NSScreen) -> NSSize {
        let aspect = screen.frame.width / screen.frame.height
        let longSide: CGFloat = 480
        if aspect >= 1 {
            return NSSize(width: longSide, height: (longSide / aspect).rounded())
        } else {
            return NSSize(width: (longSide * aspect).rounded(), height: longSide)
        }
    }

    let captureMode: CaptureMode

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(captureMode: CaptureMode, initialSize: NSSize, origin: NSPoint) {
        self.captureMode = captureMode
        super.init(
            contentRect: NSRect(origin: origin, size: initialSize),
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
        isReleasedWhenClosed = false
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

    static func loadLastPosition(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return WindowPositioning.visibleOrigin(
            preferred: savedPosition(),
            windowSize: size,
            in: screen.visibleFrame
        )
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
