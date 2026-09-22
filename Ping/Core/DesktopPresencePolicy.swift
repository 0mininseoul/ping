import Foundation

/// `ping_room_desktop_presence`가 돌려주는 한 기기의 상태.
struct DesktopPresenceRow: Decodable, Equatable {
    let uid: String
    let lastSeenAt: Date
    /// 서버가 판단한다. 기기 시계가 어긋나도 초록 점이 거짓말하지 않도록.
    let isLive: Bool
    /// 서버가 판단한다. `is_live`와 동시에 true가 되지 않는다 — 잠들었으면 접속 중이 아니다.
    let isSleeping: Bool

    enum CodingKeys: String, CodingKey {
        case uid
        case lastSeenAt = "last_seen_at"
        case isLive = "is_live"
        case isSleeping = "is_sleeping"
    }

    init(uid: String, lastSeenAt: Date, isLive: Bool, isSleeping: Bool = false) {
        self.uid = uid
        self.lastSeenAt = lastSeenAt
        self.isLive = isLive
        self.isSleeping = isSleeping
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        lastSeenAt = try container.decode(Date.self, forKey: .lastSeenAt)
        isLive = try container.decode(Bool.self, forKey: .isLive)
        // 구버전 RPC 응답과의 하위 호환. 없으면 잠자기 아님으로 취급한다.
        isSleeping = try container.decodeIfPresent(Bool.self, forKey: .isSleeping) ?? false
    }
}

/// 한 사람의 데스크톱 상태. 기기가 여러 대여도 하나로 합친다.
struct MemberPresence: Equatable {
    let isLive: Bool
    let isSleeping: Bool
    let lastSeenAt: Date

    init(isLive: Bool, isSleeping: Bool = false, lastSeenAt: Date) {
        self.isLive = isLive
        self.isSleeping = isSleeping
        self.lastSeenAt = lastSeenAt
    }
}

/// 화면에 보여줄 3단계 상태. 우선순위는 접속 중 > 잠자기 중 > 오프라인이다.
enum PresenceDisplayStatus: Equatable {
    case live
    case sleeping
    case offline(lastSeenAt: Date)
}

enum DesktopPresencePolicy {
    /// 기기별 행을 사람 단위로 합친다. 한 대라도 켜져 있으면 접속 중이고,
    /// 한 대라도 잠들어 있으면(그리고 켜져 있는 다른 기기가 없으면) 잠자기 중이다.
    /// 마지막 접속 시각은 가장 최근 기기의 것이다.
    static func merge(_ rows: [DesktopPresenceRow]) -> [String: MemberPresence] {
        var merged: [String: MemberPresence] = [:]

        for row in rows {
            guard let existing = merged[row.uid] else {
                merged[row.uid] = MemberPresence(
                    isLive: row.isLive,
                    isSleeping: row.isSleeping,
                    lastSeenAt: row.lastSeenAt
                )
                continue
            }

            merged[row.uid] = MemberPresence(
                isLive: existing.isLive || row.isLive,
                isSleeping: existing.isSleeping || row.isSleeping,
                lastSeenAt: max(existing.lastSeenAt, row.lastSeenAt)
            )
        }

        return merged
    }

    /// 접속 중 > 잠자기 중 > 오프라인 순으로 우선한다. 맥이 두 대면 하나라도
    /// 켜져 있는 쪽이 이긴다.
    static func displayStatus(_ presence: MemberPresence) -> PresenceDisplayStatus {
        if presence.isLive { return .live }
        if presence.isSleeping { return .sleeping }
        return .offline(lastSeenAt: presence.lastSeenAt)
    }

    /// 메뉴바에 세울 "접속 중" 이름들. 내 모든 방의 멤버를 합쳐서 보기 때문에
    /// 두 방에 같이 있는 사람이 두 번 나오지 않게 이름을 하나로 모은다.
    /// 잠자기 중인 사람은 여기 끼면 안 된다 — `isLive`만 본다.
    static func liveMemberNames(
        memberUids: [String],
        excluding myUid: String?,
        presence: [String: MemberPresence],
        nicknameForUid: (String) -> String
    ) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []

        for uid in memberUids where uid != myUid {
            guard presence[uid]?.isLive == true, seen.insert(uid).inserted else { continue }
            names.append(nicknameForUid(uid))
        }

        return names.sorted()
    }

    /// 오프라인 멤버 옆에 붙는 문구. 서버와 기기 시계가 어긋나 마지막 접속이
    /// 미래로 보여도 "-3분 전" 같은 문구가 나오면 안 된다.
    static func lastSeenText(_ lastSeenAt: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(lastSeenAt)
        guard elapsed >= 60 else { return "방금 전" }

        if elapsed < 3600 {
            return "\(Int(elapsed) / 60)분 전"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed) / 3600)시간 전"
        }
        return "\(Int(elapsed) / 86_400)일 전"
    }
}
