import XCTest

final class RoomVideoDeduplicationContractTests: XCTestCase {
    func testRoomMessagesDedupeSenderRowsByRoomAndVideoPath() throws {
        let migration = try readProjectSource("supabase/migrations/20260602000100_dedupe_sender_room_videos.sql")
        let functionBody = try extract(
            "create or replace function public.ping_room_messages",
            through: "grant execute on function public.ping_room_messages",
            from: migration
        )

        XCTAssertTrue(functionBody.contains("deduped_messages"))
        XCTAssertTrue(functionBody.contains("partition by m.room_id, m.video_url"))
        XCTAssertTrue(functionBody.contains("m.sender_uid = me"))
        XCTAssertTrue(functionBody.contains("m.receiver_uid = me or m.sender_uid = me"))
        XCTAssertTrue(functionBody.contains("m.sender_uid <> me or m.sender_video_rank = 1"))
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
