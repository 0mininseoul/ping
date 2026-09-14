import XCTest

/// 자동 회신 여러 개가 한 번에, 겹치지 않게 뜨는지를 배선 수준에서 지킨다.
/// 정책과 배치는 각각 단위 테스트가 있지만, AppDelegate가 그것을 안 쓰면 의미가 없다.
final class AutoReplyBatchContractTests: XCTestCase {
    func testAutoRepliesAreCollectedIntoABatchInsteadOfPlayingOnArrival() throws {
        let source = try readProjectSource("Ping/AppDelegate.swift")

        let delivery = try sourceSlice(
            in: source,
            from: "private func deliverIncomingVideo",
            to: "private func fetchIncomingVideosNow"
        )
        XCTAssertTrue(delivery.contains("if message.isAutoReply"))
        XCTAssertTrue(delivery.contains("enqueueAutoReply(message"))
    }

    func testBatchAsksThePolicyWhenToPresent() throws {
        let source = try readProjectSource("Ping/AppDelegate.swift")

        let enqueue = try sourceSlice(
            in: source,
            from: "private func enqueueAutoReply",
            to: "private func expectedAutoReplyCount"
        )
        XCTAssertTrue(enqueue.contains("AutoReplyBatchPolicy.decide"))
        XCTAssertTrue(enqueue.contains("case .present"))
        XCTAssertTrue(enqueue.contains("case .waitUntil"))
    }

    /// 기대 인원은 본인을 뺀 룸 멤버 수다. 본인을 포함하면 마지막 회신을 영영 기다린다.
    func testExpectedCountExcludesTheReceiver() throws {
        let source = try readProjectSource("Ping/AppDelegate.swift")

        let expected = try sourceSlice(
            in: source,
            from: "private func expectedAutoReplyCount",
            to: "private func cancelPlaybackPrefetches"
        )
        XCTAssertTrue(expected.contains("$0 != myUid"))
    }

    /// 창을 하나씩 만들면 좌표가 같아 포개진다. 묶음 전체를 한 번에 배치해야 한다.
    func testEveryWindowInABatchIsPlacedByTheGroupLayout() throws {
        let source = try readProjectSource("Ping/AppDelegate.swift")

        let present = try sourceSlice(
            in: source,
            from: "private func presentPlaybacks",
            to: "private func enqueueAutoReply"
        )
        XCTAssertTrue(present.contains("PlaybackGroupLayout.origins("))
        XCTAssertTrue(present.contains("window.fadeIn()"))
        XCTAssertTrue(present.contains("ForegroundPresenter.activateApp()"))
    }

    /// 계정을 바꾸면 이전 사용자의 회신이 새 계정 화면에 떠서는 안 된다.
    func testSignOutDropsPendingBatches() throws {
        let source = try readProjectSource("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("cancelPendingAutoReplyBatches()"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound, "없는 표식: \(startMarker)")
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound,
            "없는 표식: \(endMarker)"
        )
        return String(source[start..<end])
    }
}
