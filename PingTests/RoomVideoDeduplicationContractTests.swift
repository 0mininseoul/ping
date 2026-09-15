import XCTest

final class RoomVideoDeduplicationContractTests: XCTestCase {
    /// `ping_room_messages`의 최신 정의. 이 테스트가 옛 마이그레이션을 계속 읽으면
    /// 폐기된 불변식을 검증하면서 초록불로 남는다 — 지금 배포된 동작과 무관해진다.
    private static let roomMessagesMigration =
        "supabase/migrations/20260915000300_room_timeline_membership_guard.sql"

    private func roomMessagesFunctionBody() throws -> String {
        let migration = try readProjectSource(Self.roomMessagesMigration)
        return try extract(
            "create or replace function public.ping_room_messages",
            through: "grant execute on function public.ping_room_messages",
            from: migration
        )
    }

    /// 한 핑은 수신자 수만큼 행이 생긴다(팬아웃). 영상 단위로 한 번만 보여야 한다.
    func testRoomMessagesDedupeByRoomAndVideoPathForEverySender() throws {
        let functionBody = try roomMessagesFunctionBody()

        XCTAssertTrue(functionBody.contains("partition by m.room_id, m.video_url"))
        XCTAssertTrue(functionBody.contains("m.video_rank = 1"))
        // 예전에는 보낸 사람 행에만 dedup을 걸었다. 룸 전체를 보여주는 지금은
        // 모든 발신자에게 걸어야 남의 팬아웃 행이 중복으로 뜨지 않는다.
        XCTAssertFalse(
            functionBody.contains("m.sender_uid <> me or m.sender_video_rank = 1"),
            "발신자별 예외가 남아 있으면 남이 보낸 핑이 수신자 수만큼 중복된다"
        )
    }

    /// 살아남는 행이 바뀌면 알림 정리가 조용히 깨진다.
    /// `HistoryViewModel.videoIdsToMarkRead`가 `receiverUid == uid`로 대상을 고른다.
    func testRoomMessagesKeepMyOwnReceivingRowWhenDeduping() throws {
        let functionBody = try roomMessagesFunctionBody()

        XCTAssertTrue(
            functionBody.contains("order by (m.receiver_uid = me) desc"),
            "내 수신 행이 먼저 남지 않으면 룸을 열어도 알림이 지워지지 않는다"
        )
    }

    /// 숨김은 행이 아니라 영상 단위여야 한다. 팬아웃된 핑은 수신자마다 행이 따로 있어서,
    /// 내 행만 걸러내면 남의 행이 dedup을 통과해 숨김이 무력화된다.
    func testRoomMessagesHideIsScopedToTheVideoNotTheRow() throws {
        let functionBody = try roomMessagesFunctionBody()

        XCTAssertTrue(functionBody.contains("h.receiver_uid = me"))
        XCTAssertTrue(functionBody.contains("h.hidden_for_receiver = true"))
        XCTAssertTrue(functionBody.contains("h.video_url = m.video_url"))
    }

    /// 룸 전체를 보는 것은 실제 멤버로 한정한다. 가드의 폴백(예전 기록만 있는 호출자)까지
    /// 룸 전체를 받으면 룸을 떠난 사람이 전원의 메타데이터를 읽는다.
    func testRoomMessagesWidenOnlyForRealMembers() throws {
        let functionBody = try roomMessagesFunctionBody()

        XCTAssertTrue(functionBody.contains("is_member"))
        XCTAssertTrue(
            functionBody.contains("is_member or m.receiver_uid = me or m.sender_uid = me"),
            "멤버가 아니면 예전처럼 자기가 주고받은 행만 보여야 한다"
        )
    }

    func testSenderDeleteStillRemovesEveryRowForTheSharedVideoObject() throws {
        let migration = try readProjectSource("supabase/migrations/20260527000300_delete_video_message_rows_only.sql")
        let functionBody = try extract(
            "create or replace function public.ping_remove_video_message",
            through: "grant execute on function public.ping_remove_video_message",
            from: migration
        )

        XCTAssertTrue(functionBody.contains("delete from public.messages"))
        XCTAssertTrue(functionBody.contains("sender_uid = me"))
        XCTAssertTrue(functionBody.contains("video_url = video_path"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
