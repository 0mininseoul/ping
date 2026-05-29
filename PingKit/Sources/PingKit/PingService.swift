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
    func sendChat(roomId: String, body text: String) async throws -> String {
        try await rpcValue("ping_send_chat", body: [
            "room_uuid": roomId,
            "body_text": text
        ])
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
}
