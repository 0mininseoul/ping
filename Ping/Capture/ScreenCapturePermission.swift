import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
enum ScreenCapturePermission {
    enum Status {
        case authorized
        case denied
        case unknown
    }

    /// Idempotent permission check. Does NOT trigger a prompt.
    /// Reliable across ad-hoc signed builds where SCShareableContent throws spuriously.
    static func currentStatus() async -> Status {
        if CGPreflightScreenCaptureAccess() {
            return .authorized
        }
        return .denied
    }

    /// Triggers the system permission prompt if needed. Returns true if granted.
    /// macOS shows the standard "Screen Recording" prompt on first call;
    /// after denial, this returns false without prompting again — user must
    /// grant via System Settings.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
