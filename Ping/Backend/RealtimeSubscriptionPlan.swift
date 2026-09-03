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

    /// 연결이 죽은 상태에서 Realtime을 다시 시도하는 최소 간격.
    static let retryInterval: TimeInterval = 60

    /// - Parameters:
    ///   - isSocketConnected: 클라이언트 **객체**가 아니라 실제 소켓 상태다. 객체가 살아
    ///     있다는 사실은 연결을 보장하지 않는다. 객체 유무로 판단했던 0.3.66에서는 한 번
    ///     끊기면 영구히 폴링에 머물렀다(자동 재연결을 믿었지만 만료 토큰으로는 복구되지
    ///     않았다).
    ///   - lastAttemptAt: 마지막 구독 시도 시각. 재시도 간격을 재는 기준이다.
    static func plan(
        requestedRoomIds: Set<String>,
        subscribedRoomIds: Set<String>,
        state: ChatRealtimeService.ConnectionState,
        isSocketConnected: Bool,
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

        func retryIfDue() -> RealtimeSubscriptionPlan {
            guard let lastAttemptAt else { return .resubscribe }
            return now.timeIntervalSince(lastAttemptAt) >= retryInterval ? .resubscribe : .reuse
        }

        switch state {
        case .connecting:
            return .reuse
        case .disconnected:
            return .resubscribe
        case .connected:
            // 상태 모니터가 놓친 조용한 종료를 여기서 잡는다.
            return isSocketConnected ? .reuse : retryIfDue()
        case .fallbackPolling:
            // 폴백은 임시 우회여야 한다. 소켓이 살아 있지 않으면 간격을 지켜 다시 붙는다.
            return isSocketConnected ? .reuse : retryIfDue()
        }
    }
}
