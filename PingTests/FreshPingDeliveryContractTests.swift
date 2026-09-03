import XCTest
@testable import Ping

/// 룸을 여는 동작이 방금 도착한 핑의 알림을 취소하던 회귀를 막는다.
/// 서버(`ping_mark_room_read`)와 클라이언트(알림 원장) 양쪽이 같은 유예 시간을 지켜야 한다.
@MainActor final class FreshPingDeliveryContractTests: XCTestCase {
    private let uid = "receiver"
    private let now = Date()

    private func video(id: String, receiverUid: String, ageSeconds: Double?) -> VideoMessage {
        VideoMessage(
            id: id,
            roomId: "r1",
            senderUid: "sender",
            receiverUid: receiverUid,
            senderNickname: "나롱",
            videoId: "v-\(id)",
            videoUrl: "sender/v-\(id).mp4",
            durationMs: 3000,
            mirrorPosition: MirrorPosition(xRatio: 0.5, yRatio: 0.5),
            status: .uploaded,
            createdAt: ageSeconds.map { now.addingTimeInterval(-$0) },
            expiresAt: now.addingTimeInterval(3600)
        )
    }

    // MARK: - Client ledger

    func testFreshIncomingVideoIsLeftToTheNotificationPath() {
        let videos = [video(id: "fresh", receiverUid: uid, ageSeconds: 5)]
        XCTAssertEqual(HistoryViewModel.videoIdsToMarkRead(videos, uid: uid, now: now), [])
    }

    func testOlderIncomingVideoIsMarkedRead() {
        let age = PingNotificationGrace.freshVideoWindow + 1
        let videos = [video(id: "old", receiverUid: uid, ageSeconds: age)]
        XCTAssertEqual(HistoryViewModel.videoIdsToMarkRead(videos, uid: uid, now: now), ["old"])
    }

    func testBoundaryIsInclusiveOfTheGraceWindow() {
        let videos = [video(id: "edge", receiverUid: uid, ageSeconds: PingNotificationGrace.freshVideoWindow)]
        XCTAssertEqual(HistoryViewModel.videoIdsToMarkRead(videos, uid: uid, now: now), ["edge"])
    }

    func testOutgoingVideosAreNeverMarked() {
        let videos = [video(id: "mine", receiverUid: "someone-else", ageSeconds: 600)]
        XCTAssertEqual(HistoryViewModel.videoIdsToMarkRead(videos, uid: uid, now: now), [])
    }

    func testVideoWithoutATimestampIsMarkedRead() {
        let videos = [video(id: "no-ts", receiverUid: uid, ageSeconds: nil)]
        XCTAssertEqual(HistoryViewModel.videoIdsToMarkRead(videos, uid: uid, now: now), ["no-ts"])
    }

    func testMixedBatchKeepsOnlyTheFreshOne() {
        let videos = [
            video(id: "old", receiverUid: uid, ageSeconds: 600),
            video(id: "fresh", receiverUid: uid, ageSeconds: 3),
            video(id: "mine", receiverUid: "other", ageSeconds: 600)
        ]
        XCTAssertEqual(HistoryViewModel.videoIdsToMarkRead(videos, uid: uid, now: now), ["old"])
    }

    // MARK: - Server contract

    func testMarkRoomReadSkipsFreshMessages() throws {
        let migration = try readRepositoryFile(
            "supabase/migrations/20260903010000_room_read_keeps_fresh_pings.sql"
        )

        XCTAssertTrue(migration.contains("create or replace function public.ping_mark_room_read"))
        XCTAssertTrue(migration.contains("and created_at < now() - interval '60 seconds'"))
        XCTAssertTrue(migration.contains("set status = 'seen'"))
    }

    /// 두 값이 어긋나면 한쪽만 취소하는 반쪽짜리 레이스가 남는다.
    func testClientAndServerGraceWindowsAgree() throws {
        let migration = try readRepositoryFile(
            "supabase/migrations/20260903010000_room_read_keeps_fresh_pings.sql"
        )
        let seconds = Int(PingNotificationGrace.freshVideoWindow)
        XCTAssertTrue(migration.contains("interval '\(seconds) seconds'"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
