import XCTest
@testable import Ping

final class VideoMessageCodingTests: XCTestCase {
    func test_decode_screenFaceMessage_withAspectRatio() throws {
        let json = """
        {
          "id": "msg-1",
          "room_id": "room-1",
          "sender_uid": "u1",
          "receiver_uid": "u2",
          "sender_nickname": "alice",
          "video_id": "v1",
          "video_url": "u1/v1.mp4",
          "duration_ms": 3000,
          "mirror_position": {"xRatio": 0.5, "yRatio": 0.5},
          "status": "uploaded",
          "expires_at": "2030-01-01T00:00:00Z",
          "capture_mode": "screen_face",
          "aspect_ratio": 1.7777
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let msg = try decoder.decode(VideoMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.captureMode, .screenFace)
        XCTAssertEqual(msg.aspectRatio ?? 0, 1.7777, accuracy: 0.0001)
    }

    func test_decode_legacyMessage_defaultsToFaceOnly() throws {
        let json = """
        {
          "id": "msg-1",
          "room_id": "room-1",
          "sender_uid": "u1",
          "receiver_uid": "u2",
          "sender_nickname": "alice",
          "video_id": "v1",
          "video_url": "u1/v1.mp4",
          "duration_ms": 3000,
          "mirror_position": {"xRatio": 0.5, "yRatio": 0.5},
          "status": "uploaded",
          "expires_at": "2030-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let msg = try decoder.decode(VideoMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.captureMode, .faceOnly)
        XCTAssertNil(msg.aspectRatio)
    }
}
