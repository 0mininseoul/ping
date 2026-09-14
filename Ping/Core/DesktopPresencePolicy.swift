import Foundation

/// `ping_room_desktop_presence`가 돌려주는 한 기기의 상태.
struct DesktopPresenceRow: Decodable, Equatable {
    let uid: String
    let lastSeenAt: Date
    /// 서버가 판단한다. 기기 시계가 어긋나도 초록 점이 거짓말하지 않도록.
    let isLive: Bool

    enum CodingKeys: String, CodingKey {
        case uid
        case lastSeenAt = "last_seen_at"
        case isLive = "is_live"
    }
}

/// 한 사람의 데스크톱 상태. 기기가 여러 대여도 하나로 합친다.
struct MemberPresence: Equatable {
    let isLive: Bool
    let lastSeenAt: Date
}

enum DesktopPresencePolicy {
    /// 기기별 행을 사람 단위로 합친다. 한 대라도 켜져 있으면 접속 중이고,
    /// 마지막 접속 시각은 가장 최근 기기의 것이다.
    static func merge(_ rows: [DesktopPresenceRow]) -> [String: MemberPresence] {
        var merged: [String: MemberPresence] = [:]

        for row in rows {
            guard let existing = merged[row.uid] else {
                merged[row.uid] = MemberPresence(isLive: row.isLive, lastSeenAt: row.lastSeenAt)
                continue
            }

            merged[row.uid] = MemberPresence(
                isLive: existing.isLive || row.isLive,
                lastSeenAt: max(existing.lastSeenAt, row.lastSeenAt)
            )
        }

        return merged
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
