import AppKit
import ScreenCaptureKit

@MainActor
enum ScreenCapturePermission {
    enum Status {
        case authorized
        case denied
        case unknown
    }

    static func currentStatus() async -> Status {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return .authorized
        } catch {
            return .denied
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
