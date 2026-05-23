import AppKit
import CoreGraphics

@MainActor
enum ScreenCapturePermission {
    enum Status {
        case authorized
        case denied
        case unknown
    }

    /// Idempotent permission check. Does not trigger the system prompt.
    /// Do not call ScreenCaptureKit here: loading shareable content can surface
    /// the macOS recording prompt on launch before the user taps a button.
    static func currentStatus() async -> Status {
        if CGPreflightScreenCaptureAccess() {
            return .authorized
        }
        return .denied
    }

    /// Triggers the system permission prompt if needed. Returns true if granted.
    /// macOS shows the standard "Screen Recording" prompt on first call;
    /// after denial, this returns false without prompting again — user must
    /// grant via System Settings. macOS may require quitting and reopening Ping
    /// before a newly granted permission is visible to CGPreflightScreenCaptureAccess.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
