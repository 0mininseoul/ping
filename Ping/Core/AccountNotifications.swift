import Foundation

/// 설정 UI → AppDelegate 계정 인텐트. UI는 인텐트만 보내고,
/// 옵저버/창/상태를 소유한 AppDelegate가 오케스트레이션을 수행한다.
extension Notification.Name {
    static let pingSwitchAccount = Notification.Name("ping.account.switch")
    static let pingAddAccount = Notification.Name("ping.account.add")
    static let pingRemoveAccount = Notification.Name("ping.account.remove")
}

enum AccountIntentKey {
    static let userId = "userId"
}
