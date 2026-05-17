import XCTest
@testable import Ping

final class SupabaseDecodingTests: XCTestCase {
    func testDecodesRoomSummaryFromSupabaseRPCPayload() throws {
        let json = """
        {
          "id": "room-1",
          "name": "Morning",
          "searchable_name": "morning",
          "owner_uid": "user-1",
          "member_uids": ["user-1", "user-2"],
          "member_nicknames": {
            "user-1": "Youngmin",
            "user-2": "Partner"
          },
          "status": "full",
          "created_at": "2026-05-17T01:02:03Z"
        }
        """.data(using: .utf8)!

        let room = try SupabaseJSON.decoder.decode(Room.self, from: json)

        XCTAssertEqual(room.id, "room-1")
        XCTAssertEqual(room.searchableName, "morning")
        XCTAssertEqual(room.ownerUid, "user-1")
        XCTAssertEqual(room.memberUids, ["user-1", "user-2"])
        XCTAssertEqual(room.memberNicknames["user-2"], "Partner")
        XCTAssertEqual(room.status, .full)
        XCTAssertNotNil(room.createdAt)
    }

    func testDecodesVideoMessageMirrorPositionFromSupabaseRPCPayload() throws {
        let json = """
        {
          "id": "message-1",
          "room_id": "room-1",
          "sender_uid": "user-1",
          "receiver_uid": "user-2",
          "sender_nickname": "Youngmin",
          "video_id": "video-1",
          "video_url": "user-1/video-1.mp4",
          "duration_ms": 2000,
          "mirror_position": {
            "xRatio": 0.25,
            "yRatio": 0.75
          },
          "status": "uploaded",
          "created_at": "2026-05-17T01:02:03Z",
          "expires_at": "2026-05-18T01:02:03Z"
        }
        """.data(using: .utf8)!

        let message = try SupabaseJSON.decoder.decode(VideoMessage.self, from: json)

        XCTAssertEqual(message.id, "message-1")
        XCTAssertEqual(message.roomId, "room-1")
        XCTAssertEqual(message.videoUrl, "user-1/video-1.mp4")
        XCTAssertEqual(message.mirrorPosition, MirrorPosition(xRatio: 0.25, yRatio: 0.75))
        XCTAssertEqual(message.status, .uploaded)
        XCTAssertNotNil(message.createdAt)
    }

    func testStorageObjectPathUsesOwnerPrefixAndMp4Extension() {
        XCTAssertEqual(
            StorageService.videoObjectPath(senderUid: "user-1", videoId: "video-1"),
            "user-1/video-1.mp4"
        )
    }
}
