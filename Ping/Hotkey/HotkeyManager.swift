import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pingTrigger = Self("pingTrigger", default: .init(.p, modifiers: [.option]))
    static let appearanceToggle = Self("appearanceToggle", default: .init(.d, modifiers: [.option, .shift]))
    static let captureScreenFace = Self("captureScreenFace", default: .init(.l, modifiers: [.option]))
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    func register(
        onCaptureFace: @escaping @MainActor () -> Void,
        onAppearanceToggle: @escaping @MainActor () -> Void,
        onCaptureScreenFace: @escaping @MainActor () -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .pingTrigger) {
            Task { @MainActor in
                onCaptureFace()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .appearanceToggle) {
            Task { @MainActor in
                onAppearanceToggle()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .captureScreenFace) {
            Task { @MainActor in
                onCaptureScreenFace()
            }
        }
    }
}
