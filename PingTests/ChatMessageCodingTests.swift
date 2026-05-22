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
}
