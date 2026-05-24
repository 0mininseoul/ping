import Foundation

@MainActor
final class ChatMessageService {
    struct ChatMediaPayload: Hashable {
        let path: String
        let mimeType: String
        let width: Int?
        let height: Int?
        let fileName: String?
    }

    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func sendChat(
        roomId: String,
        body: String,
        replyToChatId: String? = nil,
        replyToVideoId: String? = nil,
        messageId: String? = nil,
        media: ChatMediaPayload? = nil
    ) async throws -> String {
        var rpcBody: [String: Any] = [
            "room_uuid": roomId,
            "body_text": body
        ]
        if let replyToChatId { rpcBody["reply_chat_uuid"] = replyToChatId }
        if let replyToVideoId { rpcBody["reply_video_uuid"] = replyToVideoId }
        if let messageId { rpcBody["message_uuid"] = messageId }
        if let media {
            rpcBody["media_path_text"] = media.path
            rpcBody["media_mime_type_text"] = media.mimeType
            if let width = media.width { rpcBody["media_width_int"] = width }
            if let height = media.height { rpcBody["media_height_int"] = height }
            if let fileName = media.fileName { rpcBody["media_file_name_text"] = fileName }
        }
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
