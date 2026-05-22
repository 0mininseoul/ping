import Foundation

@MainActor
final class ChatMessageService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func sendChat(roomId: String, body: String, replyToChatId: String? = nil, replyToVideoId: String? = nil) async throws -> String {
        var rpcBody: [String: Any] = [
            "room_uuid": roomId,
            "body_text": body
        ]
        if let replyToChatId { rpcBody["reply_chat_uuid"] = replyToChatId }
        if let replyToVideoId { rpcBody["reply_video_uuid"] = replyToVideoId }
        return try await client.rpcValue("ping_send_chat", body: rpcBody)
    }

    func roomChatMessages(roomId: String, beforeTimestamp: Date? = nil, limit: Int = 50) async throws -> [ChatMessage] {
        var rpcBody: [String: Any] = [
            "room_uuid": roomId,
            "page_limit": limit
        ]
        if let beforeTimestamp {
            rpcBody["before_ts"] = ISO8601DateFormatter.shared.string(from: beforeTimestamp)
        }
        return try await client.rpcArray("ping_room_chat_messages", body: rpcBody)
    }

    func deleteChat(messageId: String) async throws {
        try await client.rpcVoid("ping_delete_chat", body: ["chat_uuid": messageId])
    }

    func markRoomRead(roomId: String) async throws {
        try await client.rpcVoid("ping_mark_room_read", body: ["room_uuid": roomId])
    }

    func unreadChatCounts() async throws -> [String: Int] {
        struct Row: Codable {
            let room_id: String
            let unread_count: Int
        }
        let rows: [Row] = try await client.rpcArray("ping_unread_chat_counts")
        var map: [String: Int] = [:]
        for r in rows { map[r.room_id] = r.unread_count }
        return map
    }
}
