import Foundation

enum PingPreferenceKeys {
    static let notificationSound = "ping.notifications.sound"
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
