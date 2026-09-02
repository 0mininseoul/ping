import XCTest
@testable import Ping

final class ClientEventThrottleTests: XCTestCase {
    private let start = Date()

    func testProductEventsAreNotThrottledBackToBack() {
        var throttle = ClientEventThrottle()
        XCTAssertTrue(throttle.allows("ping_sent", now: start))
        XCTAssertTrue(throttle.allows("ping_sent", now: start))
        XCTAssertTrue(throttle.allows("ping_sent", now: start.addingTimeInterval(1)))
    }

    /// 회귀 방지: 연결 이벤트가 초 단위로 반복돼 client_events가 470MB까지 불어났다.
    func testDiagnosticEventsAreRateLimited() {
        var throttle = ClientEventThrottle()
        XCTAssertTrue(throttle.allows("realtime_disconnected", now: start))
        XCTAssertFalse(throttle.allows("realtime_disconnected", now: start.addingTimeInterval(10)))
        XCTAssertFalse(
            throttle.allows(
                "realtime_disconnected",
                now: start.addingTimeInterval(ClientEventThrottle.diagnosticInterval - 1)
            )
        )
        XCTAssertTrue(
            throttle.allows(
                "realtime_disconnected",
                now: start.addingTimeInterval(ClientEventThrottle.diagnosticInterval)
            )
        )
    }

    func testDiagnosticEventsAreThrottledIndependently() {
        var throttle = ClientEventThrottle()
        XCTAssertTrue(throttle.allows("realtime_disconnected", now: start))
        XCTAssertTrue(throttle.allows("realtime_reconnected", now: start))
    }

    /// 어떤 이벤트든 폭주하면 세션 상한에서 멈춘다.
    func testSessionCapStopsARunawayEvent() {
        var throttle = ClientEventThrottle()
        for i in 0..<ClientEventThrottle.sessionCap {
            XCTAssertTrue(
                throttle.allows("chat_received_view", now: start.addingTimeInterval(Double(i))),
                "상한 이전 \(i)번째 이벤트는 통과해야 한다"
            )
        }
        XCTAssertFalse(
            throttle.allows(
                "chat_received_view",
                now: start.addingTimeInterval(Double(ClientEventThrottle.sessionCap))
            )
        )
    }

    func testSessionCapIsPerEventName() {
        var throttle = ClientEventThrottle()
        for i in 0..<ClientEventThrottle.sessionCap {
            _ = throttle.allows("chat_received_view", now: start.addingTimeInterval(Double(i)))
        }
        XCTAssertTrue(throttle.allows("ping_sent", now: start))
    }
}
