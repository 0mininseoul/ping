import Foundation

/// A room the current identity belongs to (decoded from `ping_my_rooms`). Only
/// the fields the iOS inbox needs are modeled; extra columns are ignored.
public struct PingRoom: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let ownerUid: String
    public let memberUids: [String]
    public let memberNicknames: [String: String]
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerUid = "owner_uid"
        case memberUids = "member_uids"
        case memberNicknames = "member_nicknames"
        case createdAt = "created_at"
    }

    /// The room's display title from `myUid`'s perspective: the other members'
    /// nicknames, falling back to the room's own name.
    public func title(excluding myUid: String) -> String {
        let others = memberUids
            .filter { $0 != myUid }
            .compactMap { memberNicknames[$0] }
        return others.isEmpty ? name : others.joined(separator: ", ")
    }
}

/// A text chat row (decoded from `ping_room_chat_messages`, which returns
/// `chat_messages` rows directly).
public struct PingChatMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let roomId: String
    public let senderUid: String
    public let senderNickname: String
    public let body: String
    public let mediaPath: String?
    public let mediaMimeType: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case roomId = "room_id"
        case senderUid = "sender_uid"
        case senderNickname = "sender_nickname"
        case mediaPath = "media_path"
        case mediaMimeType = "media_mime_type"
        case createdAt = "created_at"
    }

    public var hasImage: Bool {
        guard let mediaMimeType, mediaMimeType.hasPrefix("image/") else { return false }
        return true
    }

    /// One-line preview for an inbox/notification ("사진" when image-only).
    public var preview: String {
        if !body.isEmpty { return body }
        return hasImage ? "사진" : ""
    }
}
