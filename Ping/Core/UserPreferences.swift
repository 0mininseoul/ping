import AppKit
import Foundation

enum PingPreferenceKeys {
    static let notificationSound = "ping.notifications.sound"
    static let roomSetupDeferred = "ping.rooms.setupDeferred"
    static let appearanceMode = "ping.appearance.mode"
    static let autostartUserChoice = "ping.autostart.userChoice"
    static let autoPlayReceivedVideo = "ping.playback.autoPlayReceived"
}

/// 받은 영상을 알림 클릭 없이 바로 띄울지에 대한 설정. 미설정은 켜짐으로 읽는다.
enum PingAutoPlayPreference {
    static var isEnabled: Bool {
        isEnabled(in: .standard)
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: PingPreferenceKeys.autoPlayReceivedVideo) != nil else {
            return true
        }
        return defaults.bool(forKey: PingPreferenceKeys.autoPlayReceivedVideo)
    }

    /// 앱이 뜨기 전에 쌓여 있던 핑까지 한꺼번에 재생되면 창이 여러 개 겹친다.
    /// 실행 후 도착한 것만 자동 재생하고 밀린 것은 알림으로만 알린다.
    static func shouldAutoPlay(
        messageCreatedAt: Date?,
        appStartedAt: Date,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard isEnabled(in: defaults) else { return false }
        guard let messageCreatedAt else { return false }
        return messageCreatedAt > appStartedAt
    }
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
