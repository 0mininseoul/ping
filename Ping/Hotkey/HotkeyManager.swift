import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pingTrigger = Self("pingTrigger", default: .init(.p, modifiers: [.option]))
    static let appearanceToggle = Self("appearanceToggle", default: .init(.d, modifiers: [.option, .shift]))
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    func register(
        onPress: @escaping @MainActor () -> Void,
        onAppearanceToggle: @escaping @MainActor () -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .pingTrigger) {
            Task { @MainActor in
                onPress()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .appearanceToggle) {
            Task { @MainActor in
                onAppearanceToggle()
            }
        }
    }
}
