import Foundation

/// 한 기기에 보관되는 익명 계정 하나. UI 표시용 nickname 캐시를 포함한다.
struct StoredAccount: Codable, Identifiable, Equatable {
    let userId: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var nickname: String
    let addedAt: Date

    var id: String { userId }

    init(
        userId: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        nickname: String,
        addedAt: Date
    ) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.nickname = nickname
        self.addedAt = addedAt
    }

    init(session: SupabaseSession, nickname: String, addedAt: Date = Date()) {
        self.init(
            userId: session.userId,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt,
            nickname: nickname,
            addedAt: addedAt
        )
    }

    var session: SupabaseSession {
        SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId
        )
    }
}

/// 디스크에 직렬화되는 다중 계정 상태.
struct AccountsFile: Codable, Equatable {
    private(set) var accounts: [StoredAccount]
    private(set) var activeUserId: String?

    static let empty = AccountsFile(accounts: [], activeUserId: nil)

    var activeAccount: StoredAccount? {
        accounts.first { $0.userId == activeUserId }
    }

    /// 레거시 단일 세션을 계정 #1로 이전한다.
    static func migrating(from legacy: SupabaseSession?) -> AccountsFile {
        guard let legacy else { return .empty }
        return AccountsFile(
            accounts: [StoredAccount(session: legacy, nickname: "")],
            activeUserId: legacy.userId
        )
    }

    /// 계정 추가. 같은 userId는 교체(중복 방지). activate=true면 활성으로.
    func adding(_ account: StoredAccount, activate: Bool) -> AccountsFile {
        var copy = self
        copy.accounts.removeAll { $0.userId == account.userId }
        copy.accounts.append(account)
        if activate { copy.activeUserId = account.userId }
        return copy
    }

    /// 계정 삭제. 활성 계정을 지우면 남은 첫 계정을 활성으로(없으면 nil).
    func removing(userId: String) -> AccountsFile {
        var copy = self
        copy.accounts.removeAll { $0.userId == userId }
        if copy.activeUserId == userId {
            copy.activeUserId = copy.accounts.first?.userId
        }
        return copy
    }

    /// 활성 계정 전환. 모르는 userId면 nil.
    func switching(to userId: String) -> AccountsFile? {
        guard accounts.contains(where: { $0.userId == userId }) else { return nil }
        var copy = self
        copy.activeUserId = userId
        return copy
    }

    /// 특정 계정의 표시용 닉네임 갱신.
    func updatingNickname(_ nickname: String, for userId: String) -> AccountsFile {
        var copy = self
        if let index = copy.accounts.firstIndex(where: { $0.userId == userId }) {
            copy.accounts[index].nickname = nickname
        }
        return copy
    }

    /// 세션의 토큰/만료를 반영. 없는 계정이면 추가(nickname은 빈 문자열로 시작 — 호출자가 나중에 `updatingNickname`으로 채워야 함). activateIfFirst면 활성이 비었을 때 활성으로.
    func upserting(session: SupabaseSession, activateIfFirst: Bool) -> AccountsFile {
        var copy = self
        if let index = copy.accounts.firstIndex(where: { $0.userId == session.userId }) {
            copy.accounts[index].accessToken = session.accessToken
            copy.accounts[index].refreshToken = session.refreshToken
            copy.accounts[index].expiresAt = session.expiresAt
        } else {
            copy.accounts.append(StoredAccount(session: session, nickname: ""))
        }
        if activateIfFirst, copy.activeUserId == nil {
            copy.activeUserId = session.userId
        }
        return copy
    }
}
