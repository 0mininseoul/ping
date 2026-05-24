import XCTest
@testable import Ping

final class ChatMessageCodingTests: XCTestCase {
    func test_decode_minimalChat() throws {
        let json = """
        {
          "id": "c1",
          "room_id": "r1",
          "sender_uid": "u1",
          "sender_nickname": "alice",
          "body": "hello",
          "created_at": "2026-05-22T10:00:00Z"
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let msg = try dec.decode(ChatMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.id, "c1")
        XCTAssertEqual(msg.body, "hello")
        XCTAssertNil(msg.replyToChatId)
        XCTAssertNil(msg.replyToVideoId)
    }

    func test_decode_chatWithReply() throws {
        let json = """
        {
          "id": "c2",
          "room_id": "r1",
          "sender_uid": "u2",
          "sender_nickname": "bob",
          "body": "thanks",
          "reply_to_chat_id": "c1",
          "created_at": "2026-05-22T10:01:00Z"
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let msg = try dec.decode(ChatMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.replyToChatId, "c1")
        XCTAssertNil(msg.replyToVideoId)
    }

    func test_decode_imageAttachmentChat() throws {
        let json = """
        {
          "id": "c3",
          "room_id": "r1",
          "sender_uid": "u2",
          "sender_nickname": "bob",
          "body": "",
          "media_path": "u2/chat-images/c3.jpg",
          "media_mime_type": "image/jpeg",
          "media_width": 1600,
          "media_height": 1200,
          "media_file_name": "photo.jpg",
          "created_at": "2026-05-22T10:02:00Z"
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let msg = try dec.decode(ChatMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.mediaPath, "u2/chat-images/c3.jpg")
        XCTAssertEqual(msg.mediaMimeType, "image/jpeg")
        XCTAssertEqual(msg.mediaWidth, 1600)
        XCTAssertEqual(msg.mediaHeight, 1200)
        XCTAssertEqual(msg.mediaFileName, "photo.jpg")
        XCTAssertTrue(msg.hasImageAttachment)
    }
}
