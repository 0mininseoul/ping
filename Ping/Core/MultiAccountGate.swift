import Foundation

/// 다중 계정 스위처 노출 게이트. 활성 닉네임이 오너(`영민`)면 기기 로컬 플래그를 켠다.
/// 한 번 켜지면 유지되어, 비-오너 계정으로 전환해도 스위처가 사라져 갇히지 않는다.
enum MultiAccountGate {
    static let unlockedKey = "ping.multiAccount.unlocked"
    static let ownerNickname = "영민"

    static func isUnlocked(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: unlockedKey)
    }

    @discardableResult
    static func updateUnlock(forNickname nickname: String, defaults: UserDefaults = .standard) -> Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == ownerNickname {
            defaults.set(true, forKey: unlockedKey)
        }
        return isUnlocked(defaults: defaults)
    }
}
