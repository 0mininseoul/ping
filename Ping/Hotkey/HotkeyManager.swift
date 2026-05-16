import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pingTrigger = Self("pingTrigger", default: .init(.p, modifiers: [.option]))
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    func register(onPress: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .pingTrigger) {
            Task { @MainActor in
                onPress()
            }
        }
    }
}
