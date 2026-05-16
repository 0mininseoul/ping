import AppKit
import SwiftUI

@MainActor
final class OnboardingWindow: NSWindow {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Ping 시작하기"
        contentView = NSHostingView(rootView: rootView)
        isReleasedWhenClosed = false
        center()
    }
}
