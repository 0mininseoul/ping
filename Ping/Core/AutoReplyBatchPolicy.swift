import Foundation

/// 한 핑에 달린 자동 회신을 몇 개 모았다가 언제 한 번에 띄울지 정한다.
///
/// 준비되는 대로 하나씩 띄우면 회신이 한 명씩 순서대로 뜬다. 반대로 전원을 무한정 기다리면
/// 설정을 꺼둔 사람 하나 때문에 아무것도 안 뜬다. 그래서 "룸의 나머지 인원이 다 모이면 즉시,
/// 아니면 수집 창이 끝날 때"로 자른다. 1:1 룸은 첫 회신에서 바로 떠 지연이 0이다.
enum AutoReplyBatchPolicy {
    /// 상대는 얼굴 3초를 녹화한 뒤 올리므로 회신 사이의 도착 간격은 업로드 시간 차이가 거의 전부다.
    static let collectionWindow: TimeInterval = 5

    enum Decision: Equatable {
        case present
        case waitUntil(Date)
    }

    /// - Parameters:
    ///   - collected: 지금까지 모인 회신 수.
    ///   - expected: 이 룸에서 회신이 올 수 있는 최대 인원(본인 제외 멤버 수). 모르면 0.
    ///   - firstArrivedAt: 묶음의 첫 회신이 준비된 시각. 마감은 항상 여기에 고정한다 —
    ///     마지막 도착 기준으로 미루면 회신이 들어오는 동안 영영 안 뜬다.
    static func decide(collected: Int, expected: Int, firstArrivedAt: Date) -> Decision {
        if collected >= max(1, expected) { return .present }
        return .waitUntil(firstArrivedAt.addingTimeInterval(collectionWindow))
    }
}
