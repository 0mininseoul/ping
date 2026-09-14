import XCTest
@testable import Ping

final class AutoReplyBatchPolicyTests: XCTestCase {
    private let firstArrival = Date(timeIntervalSince1970: 1_000)
    private var deadline: Date { firstArrival.addingTimeInterval(AutoReplyBatchPolicy.collectionWindow) }

    /// 1:1 룸은 회신이 한 명뿐이라 모을 것이 없다. 여기서 기다리면 가장 흔한 경우가 느려진다.
    func testOneOnOneRoomPresentsTheFirstReplyImmediately() {
        XCTAssertEqual(
            AutoReplyBatchPolicy.decide(collected: 1, expected: 1, firstArrivedAt: firstArrival),
            .present
        )
    }

    func testGroupRoomHoldsTheFirstReplyUntilTheRestCanArrive() {
        XCTAssertEqual(
            AutoReplyBatchPolicy.decide(collected: 1, expected: 2, firstArrivedAt: firstArrival),
            .waitUntil(deadline)
        )
    }

    func testGroupRoomPresentsAsSoonAsEveryoneHasReplied() {
        XCTAssertEqual(
            AutoReplyBatchPolicy.decide(collected: 2, expected: 2, firstArrivedAt: firstArrival),
            .present
        )
    }

    /// 마감이 마지막 도착 기준이면 회신이 꾸준히 들어오는 동안 영원히 안 뜬다.
    func testDeadlineIsAnchoredToTheFirstArrival() {
        let waitedOnce = AutoReplyBatchPolicy.decide(collected: 1, expected: 3, firstArrivedAt: firstArrival)
        let waitedAgain = AutoReplyBatchPolicy.decide(collected: 2, expected: 3, firstArrivedAt: firstArrival)

        XCTAssertEqual(waitedOnce, waitedAgain)
        XCTAssertEqual(waitedAgain, .waitUntil(deadline))
    }

    /// 룸 목록을 아직 못 받았으면 기대 인원을 0으로 넘긴다. 그때 멈춰 서면 안 된다.
    func testUnknownRoomSizeDoesNotStallThePresentation() {
        XCTAssertEqual(
            AutoReplyBatchPolicy.decide(collected: 1, expected: 0, firstArrivedAt: firstArrival),
            .present
        )
    }

    /// 룸에서 나간 사람의 회신이 뒤늦게 섞이면 모인 수가 기대치를 넘을 수 있다.
    func testMoreRepliesThanExpectedStillPresent() {
        XCTAssertEqual(
            AutoReplyBatchPolicy.decide(collected: 3, expected: 2, firstArrivedAt: firstArrival),
            .present
        )
    }

    /// 상대는 3초를 녹화한 뒤 올린다. 도착 간격은 업로드 시간 차이가 거의 전부라
    /// 창이 너무 짧으면 두 번째 얼굴이 다음 묶음으로 밀린다.
    func testCollectionWindowCoversTheUploadSkewAfterAThreeSecondClip() {
        XCTAssertGreaterThanOrEqual(AutoReplyBatchPolicy.collectionWindow, 3)
        XCTAssertLessThanOrEqual(AutoReplyBatchPolicy.collectionWindow, 10)
    }
}
