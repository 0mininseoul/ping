import Foundation

/// 룸 폴링은 10초마다 같은 목록을 다시 흘려보낸다. 그때마다 Realtime을 다시 붙으면
/// 이전 클라이언트와 상태 모니터 task가 정리되지 않은 채 쌓이고, 좀비 모니터가 계속
/// 연결 이벤트를 남겨 Free 플랜 용량을 갉아먹는다. 재구독 여부를 여기서 한 번에 정한다.
enum RealtimeSubscriptionPlan: Equatable {
    /// 같은 룸 집합에 이미 붙어 있거나 붙는 중이다. 아무것도 하지 않는다.
    case reuse
    /// 룸 집합이 바뀌었거나 연결이 끊겼다. 기존 연결을 걷어내고 새로 붙는다.
    case resubscribe
    /// 구독할 룸이 없다.
    case unsubscribe

    /// 초기 연결에 실패해 살아 있는 클라이언트가 없을 때 Realtime을 다시 시도하는 간격.
    static let retryInterval: TimeInterval = 60

    /// - Parameters:
    ///   - hasLiveClient: 클라이언트가 남아 있으면 스스로 재연결하므로 폴링 폴백 중에도
    ///     새로 붙을 필요가 없다. 초기 연결 실패는 클라이언트를 남기지 않는다.
    ///   - lastAttemptAt: 마지막 구독 시도 시각. 클라이언트 없이 폴링만 도는 상태에서
    ///     재시도 간격을 재는 기준이다.
    static func plan(
        requestedRoomIds: Set<String>,
        subscribedRoomIds: Set<String>,
        state: ChatRealtimeService.ConnectionState,
        hasLiveClient: Bool,
        lastAttemptAt: Date?,
        now: Date = Date(),
        retryInterval: TimeInterval = RealtimeSubscriptionPlan.retryInterval
    ) -> RealtimeSubscriptionPlan {
        if requestedRoomIds.isEmpty {
            // 이미 아무것도 붙어 있지 않으면 매 폴링마다 해지를 반복할 이유가 없다.
            let isAlreadyIdle = subscribedRoomIds.isEmpty && state == .disconnected
            return isAlreadyIdle ? .reuse : .unsubscribe
        }

        if requestedRoomIds != subscribedRoomIds {
            return .resubscribe
        }

        switch state {
        case .connected, .connecting:
            return .reuse
        case .disconnected:
            return .resubscribe
        case .fallbackPolling:
            if hasLiveClient {
                // 클라이언트가 살아 있으면 재연결과 상태 모니터가 복구를 맡는다.
                return .reuse
            }
            guard let lastAttemptAt else { return .resubscribe }
            return now.timeIntervalSince(lastAttemptAt) >= retryInterval ? .resubscribe : .reuse
        }
    }
}
