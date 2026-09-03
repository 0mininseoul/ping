import XCTest
@testable import Ping

final class RealtimeSubscriptionPlanTests: XCTestCase {
    private let rooms: Set<String> = ["a", "b"]
    private let now = Date()

    private func plan(
        requested: Set<String>? = nil,
        subscribed: Set<String>? = nil,
        state: ChatRealtimeService.ConnectionState,
        isSocketConnected: Bool = true,
        lastAttemptAt: Date? = nil
    ) -> RealtimeSubscriptionPlan {
        RealtimeSubscriptionPlan.plan(
            requestedRoomIds: requested ?? rooms,
            subscribedRoomIds: subscribed ?? rooms,
            state: state,
            isSocketConnected: isSocketConnected,
            lastAttemptAt: lastAttemptAt ?? now,
            now: now
        )
    }

    /// 회귀 방지: 10초 폴링이 같은 목록을 다시 흘려도 재구독하면 안 된다.
    /// 재구독마다 Realtime 클라이언트와 모니터 task가 누수돼 텔레메트리가 폭주했다.
    func testUnchangedRoomsOnAConnectedClientAreReused() {
        XCTAssertEqual(plan(state: .connected), .reuse)
    }

    func testUnchangedRoomsWhileConnectingAreReused() {
        XCTAssertEqual(plan(state: .connecting), .reuse)
    }

    /// 소켓이 실제로 붙어 있으면 굳이 다시 붙지 않는다.
    func testPollingFallbackWithALiveSocketIsReused() {
        XCTAssertEqual(plan(state: .fallbackPolling, isSocketConnected: true), .reuse)
    }

    /// 회귀 방지: 0.3.66은 클라이언트 **객체**가 남아 있으면 자동 재연결을 믿고
    /// 아무것도 하지 않았다. 만료된 토큰으로는 복구되지 않아 한 번 끊기면 영구히
    /// 10초 폴링에 머물렀다(영상 전달이 0.7초 → 10.1초로 되돌아감).
    func testPollingFallbackWithADeadSocketRetriesAfterTheInterval() {
        XCTAssertEqual(
            plan(
                state: .fallbackPolling,
                isSocketConnected: false,
                lastAttemptAt: now.addingTimeInterval(-RealtimeSubscriptionPlan.retryInterval - 1)
            ),
            .resubscribe
        )
    }

    func testPollingFallbackWithADeadSocketWaitsForTheRetryInterval() {
        XCTAssertEqual(
            plan(
                state: .fallbackPolling,
                isSocketConnected: false,
                lastAttemptAt: now.addingTimeInterval(-10)
            ),
            .reuse
        )
    }

    /// 상태 모니터가 조용한 종료를 놓쳐 .connected로 남아 있어도 복구한다.
    func testConnectedStateWithADeadSocketRetriesAfterTheInterval() {
        XCTAssertEqual(
            plan(
                state: .connected,
                isSocketConnected: false,
                lastAttemptAt: now.addingTimeInterval(-RealtimeSubscriptionPlan.retryInterval - 1)
            ),
            .resubscribe
        )
    }

    func testDisconnectedClientResubscribes() {
        XCTAssertEqual(plan(state: .disconnected), .resubscribe)
    }

    func testAddedRoomResubscribes() {
        XCTAssertEqual(plan(requested: rooms.union(["c"]), state: .connected), .resubscribe)
    }

    func testRemovedRoomResubscribes() {
        XCTAssertEqual(plan(requested: ["a"], state: .connected), .resubscribe)
    }

    func testRoomOrderIsNotAChange() {
        XCTAssertEqual(
            plan(requested: Set(["b", "a"]), subscribed: Set(["a", "b"]), state: .connected),
            .reuse
        )
    }

    func testNoRoomsUnsubscribes() {
        XCTAssertEqual(plan(requested: [], state: .connected), .unsubscribe)
    }

    /// 룸이 하나도 없는 계정에서 10초마다 해지를 반복하지 않는다.
    func testAlreadyIdleStaysIdle() {
        XCTAssertEqual(
            plan(requested: [], subscribed: [], state: .disconnected, isSocketConnected: false),
            .reuse
        )
    }

    // MARK: - Source contracts

    /// 회귀 방지: 재구독 전에 이전 클라이언트와 모니터 task를 걷어내지 않으면
    /// 좀비 모니터가 쌓여 연결 이벤트로 DB를 채운다.
    func testSubscribeTearsDownBeforeBuildingANewClient() throws {
        let source = try readRepositoryFile("Ping/Backend/ChatRealtimeService.swift")

        let subscribeBody = try sourceSlice(
            in: source,
            from: "    func subscribe(",
            to: "    func unsubscribeAll()"
        )
        let teardown = try XCTUnwrap(subscribeBody.range(of: "await tearDownRealtime()"))
        let connect = try XCTUnwrap(subscribeBody.range(of: "await tryRealtime("))
        XCTAssertLessThan(teardown.lowerBound, connect.lowerBound)

        XCTAssertTrue(source.contains("realtimeMonitorTask?.cancel()"))
        XCTAssertTrue(source.contains("await client.disconnect()"))
        XCTAssertTrue(source.contains("connectionGeneration &+= 1"))
    }

    /// 회귀 방지: 토큰을 캡처해 두면 jwt_exp(1시간) 뒤 재인증이 실패해 소켓이 닫히고,
    /// 재연결도 같은 만료 토큰을 쓰므로 영구히 복구되지 않는다.
    func testRealtimeReadsTheAccessTokenLazily() throws {
        let source = try readRepositoryFile("Ping/Backend/ChatRealtimeService.swift")

        XCTAssertTrue(source.contains("await SupabaseClient.shared.currentAccessToken()"))
        XCTAssertFalse(source.contains("return { sendableTok }"))
    }

    /// 룸 폴링이 같은 목록을 흘릴 때 세션 토큰 조회까지 건너뛴다.
    func testRoomPollingSkipsSubscriptionWorkWhenAlreadyConnected() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("chatRealtime.needsSubscription(roomIds: roomIds)"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
