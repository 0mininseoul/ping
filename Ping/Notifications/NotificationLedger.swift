import Foundation

/// 계정별·종류별로 격리된 알림 dedup 원장. 같은 알림을 전환마다 재발송하지 않도록
/// 이미 알린 ID를 UserDefaults에 영속한다.
@MainActor struct NotificationLedger {
    enum Kind: String {
        case video
        case invite
        case chat

        var baseKey: String {
            switch self {
            case .video: return "ping.notifications.notifiedMessageIds"
            case .invite: return "ping.notifications.notifiedInviteIds"
            case .chat: return "ping.notifications.notifiedChatIds"
            }
        }
    }

    private let defaults: UserDefaults
    private let cap: Int

    // cap: UserDefaults 쓰기 크기/메모리를 제한. 300은 통상 세션 알림량을 넉넉히 상회.
    init(defaults: UserDefaults = .standard, cap: Int = 300) {
        self.defaults = defaults
        self.cap = cap
    }

    private func key(_ kind: Kind, uid: String) -> String {
        "\(kind.baseKey):\(uid)"
    }

    func ids(_ kind: Kind, uid: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key(kind, uid: uid)) ?? [])
    }

    func contains(_ kind: Kind, uid: String, id: String) -> Bool {
        (defaults.stringArray(forKey: key(kind, uid: uid)) ?? []).contains(id)
    }

    /// 주의: 쓰기는 `defaults`를 통해 일어나므로 `let` 바인딩에서도 호출 가능하다.
    func remember(_ kind: Kind, uid: String, id: String) {
        let storageKey = key(kind, uid: uid)
        var ordered = defaults.stringArray(forKey: storageKey) ?? []
        // 중복 제거하면서 최근 추가를 끝으로 유지.
        ordered.removeAll { $0 == id }
        ordered.append(id)
        if ordered.count > cap {
            ordered = Array(ordered.suffix(cap))
        }
        defaults.set(ordered, forKey: storageKey)
    }
}
