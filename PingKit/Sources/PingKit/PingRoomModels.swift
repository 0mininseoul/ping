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
    public let replyToChatId: String?
    public let replyToVideoId: String?
    public let mediaPath: String?
    public let mediaMimeType: String?
    public let mediaWidth: Int?
    public let mediaHeight: Int?
    public let mediaFileName: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case roomId = "room_id"
        case senderUid = "sender_uid"
        case senderNickname = "sender_nickname"
        case replyToChatId = "reply_to_chat_id"
        case replyToVideoId = "reply_to_video_id"
        case mediaPath = "media_path"
        case mediaMimeType = "media_mime_type"
        case mediaWidth = "media_width"
        case mediaHeight = "media_height"
        case mediaFileName = "media_file_name"
        case createdAt = "created_at"
    }

    public var hasImage: Bool {
        guard let mediaPath, !mediaPath.isEmpty,
              let mediaMimeType, mediaMimeType.hasPrefix("image/") else { return false }
        return true
    }

    /// One-line preview for an inbox/notification ("사진" when image-only).
    public var preview: String {
        if !body.isEmpty { return body }
        return hasImage ? "사진" : ""
    }

    public var mediaFileExtension: String {
        guard let mediaPath else { return "img" }
        let ext = URL(fileURLWithPath: mediaPath).pathExtension.lowercased()
        if !ext.isEmpty { return ext }

        switch mediaMimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "img"
        }
    }
}

public struct PingMessageReaction: Codable, Sendable, Identifiable, Equatable {
    public enum TargetKind: String, Codable, Sendable {
        case chat
        case video
    }

    public let targetKind: TargetKind
    public let targetId: String
    public let emoji: String
    public let totalCount: Int
    public let myReacted: Bool

    public var id: String { "\(targetKind.rawValue):\(targetId):\(emoji)" }

    enum CodingKeys: String, CodingKey {
        case targetKind = "target_kind"
        case targetId = "target_id"
        case emoji
        case totalCount = "total_count"
        case myReacted = "my_reacted"
    }
}
