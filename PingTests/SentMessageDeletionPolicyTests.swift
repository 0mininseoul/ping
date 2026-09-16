import XCTest
@testable import Ping

final class SentMessageDeletionPolicyTests: XCTestCase {
    private let sentAt = Date(timeIntervalSince1970: 1_000_000)

    func testSenderCanDeleteRightAfterSending() {
        XCTAssertTrue(
            SentMessageDeletionPolicy.canDelete(createdAt: sentAt, now: sentAt.addingTimeInterval(10))
        )
    }

    func testWindowIsFiveMinutesInclusive() {
        XCTAssertEqual(SentMessageDeletionPolicy.window, 5 * 60)
        XCTAssertTrue(
            SentMessageDeletionPolicy.canDelete(createdAt: sentAt, now: sentAt.addingTimeInterval(5 * 60))
        )
        XCTAssertFalse(
            SentMessageDeletionPolicy.canDelete(createdAt: sentAt, now: sentAt.addingTimeInterval(5 * 60 + 1))
        )
    }

    /// 시각을 모르는 메시지는 5분 안인지 판단할 수 없다. 서버가 어차피 거절하므로 메뉴를 띄우지 않는다.
    func testCannotDeleteWithoutATimestamp() {
        XCTAssertFalse(SentMessageDeletionPolicy.canDelete(createdAt: nil, now: sentAt))
    }

    /// 서버 시각이 내 맥 시계보다 조금 앞서면 방금 보낸 메시지가 "미래"로 보인다. 그래도 지울 수 있어야 한다.
    func testClockSkewTowardTheFutureStillCountsAsFresh() {
        XCTAssertTrue(
            SentMessageDeletionPolicy.canDelete(createdAt: sentAt, now: sentAt.addingTimeInterval(-3))
        )
    }

    func testRecognizesTheServerWindowRejection() {
        let rejection = PingError.supabaseRequestFailed(
            statusCode: 403,
            message: #"{"code":"42501","message":"delete_window_expired"}"#
        )
        XCTAssertTrue(SentMessageDeletionPolicy.isWindowExpired(rejection))
    }

    func testDoesNotMistakeOtherFailuresForTheWindowRejection() {
        let other = PingError.supabaseRequestFailed(statusCode: 403, message: "only sender can delete")
        XCTAssertFalse(SentMessageDeletionPolicy.isWindowExpired(other))
        XCTAssertFalse(SentMessageDeletionPolicy.isWindowExpired(URLError(.timedOut)))
    }
}
