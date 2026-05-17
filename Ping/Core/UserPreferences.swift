import AppKit
import Foundation

enum PingPreferenceKeys {
    static let notificationSound = "ping.notifications.sound"
    static let roomSetupDeferred = "ping.rooms.setupDeferred"
    static let appearanceMode = "ping.appearance.mode"
}

enum PingNotificationSound: String, CaseIterable, Identifiable {
    case systemDefault = "default"
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault:
            return "기본"
        case .none:
            return "없음"
        }
    }

    static var current: PingNotificationSound {
        let raw = UserDefaults.standard.string(forKey: PingPreferenceKeys.notificationSound)
        return PingNotificationSound(rawValue: raw ?? systemDefault.rawValue) ?? .systemDefault
    }
}

enum PingAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "시스템"
        case .light:
            return "라이트"
        case .dark:
            return "다크"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    static var current: PingAppearanceMode {
        let raw = UserDefaults.standard.string(forKey: PingPreferenceKeys.appearanceMode)
        return PingAppearanceMode(rawValue: raw ?? system.rawValue) ?? .system
    }

    @MainActor
    static func applyCurrent() {
        current.apply()
    }

    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }

    @MainActor
    static func toggleLightDark() {
        let next: PingAppearanceMode = current == .dark ? .light : .dark
        UserDefaults.standard.set(next.rawValue, forKey: PingPreferenceKeys.appearanceMode)
        next.apply()
    }
}
