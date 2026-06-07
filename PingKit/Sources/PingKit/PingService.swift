import Foundation

/// High-level operations the iOS/watch receive+reply flow needs, expressed in
/// terms of the backend RPC contract. Thin wrappers over the client so call
/// sites read intent, not RPC argument names.
public extension PingSupabaseClient {
    /// Register this device's APNs token for the current user (P1 backend).
    func registerDeviceToken(_ token: String, platform: String, environment: String) async throws {
        try await rpcVoid("ping_register_device_token", body: [
            "token_text": token,
            "platform_text": platform,
            "environment_text": environment
        ])
    }

    func removeDeviceToken(_ token: String) async throws {
        try await rpcVoid("ping_remove_device_token", body: ["token_text": token])
    }

    /// Send a text chat (the STT reply target) to a room. Returns the chat id.
    @discardableResult
    func sendChat(
        roomId: String,
        body text: String,
        replyToChatId: String? = nil,
        replyToVideoId: String? = nil
    ) async throws -> String {
        var body: [String: any Sendable] = [
            "room_uuid": roomId,
            "body_text": text
        ]
        if let replyToChatId {
            body["reply_chat_uuid"] = replyToChatId
        }
        if let replyToVideoId {
            body["reply_video_uuid"] = replyToVideoId
        }
        return try await rpcValue("ping_send_chat", body: body)
    }

    /// Fetch the latest metadata for a single message (e.g. from a push payload).
    func getMessage(messageId: String) async throws -> VideoMessage? {
        let rows: [VideoMessage] = try await rpcArray("ping_get_message", body: [
            "message_uuid": messageId
        ])
        return rows.first
    }

    /// Mark a message seen after playback (syncs with the desktop history).
    func markSeen(messageId: String) async throws {
        try await rpcVoid("ping_mark_message_seen", body: ["message_uuid": messageId])
    }

    /// Download the 3-second clip's bytes from the private `ping-videos` bucket.
    func downloadVideo(_ message: VideoMessage) async throws -> Data {
        try await downloadData(bucket: "ping-videos", path: message.storagePath)
    }

    /// Download a private chat image attachment from the `ping-media` bucket.
    func downloadChatMedia(path: String) async throws -> Data {
        try await downloadData(bucket: "ping-media", path: path)
    }

    // MARK: - Inbox / thread reads (iOS companion)

    /// Rooms the current identity belongs to (inbox list).
    func myRooms() async throws -> [PingRoom] {
        try await rpcArray("ping_my_rooms")
    }

    /// Persist the user's manual room order across Ping clients.
    func reorderMyRooms(roomIds: [String]) async throws {
        try await rpcVoid("ping_reorder_my_rooms", body: ["room_ids": roomIds])
    }

    /// Recent video messages in a room (backend returns newest-first).
    func roomMessages(roomId: String, limit: Int = 50) async throws -> [VideoMessage] {
        let messages: [VideoMessage] = try await rpcArray("ping_room_messages", body: [
            "room_uuid": roomId,
            "page_limit": limit
        ])
        return VideoMessage.dedupedSenderRows(messages, currentUid: currentSession().userId)
    }

    /// Recent text chat in a room.
    func roomChatMessages(roomId: String, limit: Int = 50) async throws -> [PingChatMessage] {
        try await rpcArray("ping_room_chat_messages", body: [
            "room_uuid": roomId,
            "page_limit": limit
        ])
    }

    /// Toggle an emoji reaction for a chat or video message.
    @discardableResult
    func toggleReaction(target kind: PingMessageReaction.TargetKind, targetId: String, emoji: String) async throws -> Bool {
        try await rpcValue("ping_react", body: [
            "target_kind": kind.rawValue,
            "target_uuid": targetId,
            "emoji_text": emoji
        ])
    }

    /// Fetch grouped reaction counts for currently visible thread items.
    func messageReactions(chatIds: [String], videoIds: [String]) async throws -> [PingMessageReaction] {
        try await rpcArray("ping_message_reactions", body: [
            "chat_ids": chatIds,
            "video_ids": videoIds
        ])
    }

    /// Clear a room's unread chat badge after the user views the thread.
    func markRoomRead(roomId: String) async throws {
        try await rpcVoid("ping_mark_room_read", body: ["room_uuid": roomId])
    }
}
