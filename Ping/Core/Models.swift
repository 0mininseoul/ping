import Foundation

enum CaptureMode: String, Codable, Hashable {
    case faceOnly = "face_only"
    case screenFace = "screen_face"
}

struct MirrorPosition: Codable, Equatable, Hashable {
    var xRatio: Double
    var yRatio: Double
}

struct PingUser: Codable, Identifiable, Hashable {
    var id: String?
    var nickname: String
    var searchableNickname: String
    var rooms: [String]
    var lastUsedRoomId: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case searchableNickname = "searchable_nickname"
        case rooms
        case lastUsedRoomId = "last_used_room_id"
        case createdAt = "created_at"
    }

    init(
        id: String? = nil,
        nickname: String,
        searchableNickname: String,
        rooms: [String] = [],
        lastUsedRoomId: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.searchableNickname = searchableNickname
        self.rooms = rooms
        self.lastUsedRoomId = lastUsedRoomId
        self.createdAt = createdAt
    }
}

struct Room: Codable, Identifiable, Hashable {
    var id: String?
    var name: String
    var searchableName: String
    var ownerUid: String
    var memberUids: [String]
    var memberNicknames: [String: String]
    var status: RoomStatus
    var createdAt: Date?
    var roomOrder: Int?
    var unreadCount: Int
    var latestUnreadAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case searchableName = "searchable_name"
        case ownerUid = "owner_uid"
        case memberUids = "member_uids"
        case memberNicknames = "member_nicknames"
        case status
        case createdAt = "created_at"
        case roomOrder = "room_order"
        case unreadCount = "unread_count"
        case latestUnreadAt = "latest_unread_at"
    }

    init(
        id: String? = nil,
        name: String,
        searchableName: String,
        ownerUid: String,
        memberUids: [String],
        memberNicknames: [String: String],
        status: RoomStatus,
        createdAt: Date? = nil,
        roomOrder: Int? = nil,
        unreadCount: Int = 0,
        latestUnreadAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.searchableName = searchableName
        self.ownerUid = ownerUid
        self.memberUids = memberUids
        self.memberNicknames = memberNicknames
        self.status = status
        self.createdAt = createdAt
        self.roomOrder = roomOrder
        self.unreadCount = unreadCount
        self.latestUnreadAt = latestUnreadAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        searchableName = try c.decode(String.self, forKey: .searchableName)
        ownerUid = try c.decode(String.self, forKey: .ownerUid)
        memberUids = try c.decode([String].self, forKey: .memberUids)
        memberNicknames = try c.decode([String: String].self, forKey: .memberNicknames)
        status = try c.decode(RoomStatus.self, forKey: .status)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        roomOrder = try c.decodeIfPresent(Int.self, forKey: .roomOrder)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        latestUnreadAt = try c.decodeIfPresent(Date.self, forKey: .latestUnreadAt)
    }
}

enum RoomStatus: String, Codable, Hashable {
    case open
    case full
}

struct VideoMessage: Codable, Identifiable, Hashable {
    var id: String?
    var roomId: String
    var senderUid: String
    var receiverUid: String
    var senderNickname: String
    var videoId: String
    var videoUrl: String
    var durationMs: Int
    var mirrorPosition: MirrorPosition
    var status: MessageStatus
    var createdAt: Date?
    var expiresAt: Date
    var captureMode: CaptureMode
    var aspectRatio: Double?
    var allowsLocalSave: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderUid = "sender_uid"
        case receiverUid = "receiver_uid"
        case senderNickname = "sender_nickname"
        case videoId = "video_id"
        case videoUrl = "video_url"
        case durationMs = "duration_ms"
        case mirrorPosition = "mirror_position"
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case captureMode = "capture_mode"
        case aspectRatio = "aspect_ratio"
        case allowsLocalSave = "allows_local_save"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.roomId = try c.decode(String.self, forKey: .roomId)
        self.senderUid = try c.decode(String.self, forKey: .senderUid)
        self.receiverUid = try c.decode(String.self, forKey: .receiverUid)
        self.senderNickname = try c.decode(String.self, forKey: .senderNickname)
        self.videoId = try c.decode(String.self, forKey: .videoId)
        self.videoUrl = try c.decode(String.self, forKey: .videoUrl)
        self.durationMs = try c.decode(Int.self, forKey: .durationMs)
        self.mirrorPosition = try c.decode(MirrorPosition.self, forKey: .mirrorPosition)
        self.status = try c.decode(MessageStatus.self, forKey: .status)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        self.captureMode = try c.decodeIfPresent(CaptureMode.self, forKey: .captureMode) ?? .faceOnly
        self.aspectRatio = try c.decodeIfPresent(Double.self, forKey: .aspectRatio)
        self.allowsLocalSave = try c.decodeIfPresent(Bool.self, forKey: .allowsLocalSave) ?? false
    }

    init(
        id: String? = nil,
        roomId: String,
        senderUid: String,
        receiverUid: String,
        senderNickname: String,
        videoId: String,
        videoUrl: String,
        durationMs: Int,
        mirrorPosition: MirrorPosition,
        status: MessageStatus,
        createdAt: Date? = nil,
        expiresAt: Date,
        captureMode: CaptureMode = .faceOnly,
        aspectRatio: Double? = nil,
        allowsLocalSave: Bool = false
    ) {
        self.id = id
        self.roomId = roomId
        self.senderUid = senderUid
        self.receiverUid = receiverUid
        self.senderNickname = senderNickname
        self.videoId = videoId
        self.videoUrl = videoUrl
        self.durationMs = durationMs
        self.mirrorPosition = mirrorPosition
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.captureMode = captureMode
        self.aspectRatio = aspectRatio
        self.allowsLocalSave = allowsLocalSave
    }

    func canBeSavedLocally(by uid: String?) -> Bool {
        if let uid, senderUid == uid {
            return true
        }
        return allowsLocalSave
    }
}

enum MessageStatus: String, Codable, Hashable {
    case uploaded
    case seen
}

struct Invitation: Codable, Identifiable, Hashable {
    var id: String?
    var fromUid: String
    var toUid: String
    var roomId: String
    var fromNickname: String
    var roomName: String
    var createdAt: Date?
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fromUid = "from_uid"
        case toUid = "to_uid"
        case roomId = "room_id"
        case fromNickname = "from_nickname"
        case roomName = "room_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct InviteLink: Codable, Identifiable, Hashable {
    var token: String
    var roomId: String
    var roomName: String
    var inviterNickname: String
    var expiresAt: Date

    var id: String { token }

    enum CodingKeys: String, CodingKey {
        case token
        case roomId = "room_id"
        case roomName = "room_name"
        case inviterNickname = "inviter_nickname"
        case expiresAt = "expires_at"
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String?
    var roomId: String
    var senderUid: String
    var senderNickname: String
    var body: String
    var replyToChatId: String?
    var replyToVideoId: String?
    var mediaPath: String?
    var mediaMimeType: String?
    var mediaWidth: Int?
    var mediaHeight: Int?
    var mediaFileName: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderUid = "sender_uid"
        case senderNickname = "sender_nickname"
        case body
        case replyToChatId = "reply_to_chat_id"
        case replyToVideoId = "reply_to_video_id"
        case mediaPath = "media_path"
        case mediaMimeType = "media_mime_type"
        case mediaWidth = "media_width"
        case mediaHeight = "media_height"
        case mediaFileName = "media_file_name"
        case createdAt = "created_at"
    }

    init(
        id: String? = nil,
        roomId: String,
        senderUid: String,
        senderNickname: String,
        body: String,
        replyToChatId: String? = nil,
        replyToVideoId: String? = nil,
        mediaPath: String? = nil,
        mediaMimeType: String? = nil,
        mediaWidth: Int? = nil,
        mediaHeight: Int? = nil,
        mediaFileName: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.senderUid = senderUid
        self.senderNickname = senderNickname
        self.body = body
        self.replyToChatId = replyToChatId
        self.replyToVideoId = replyToVideoId
        self.mediaPath = mediaPath
        self.mediaMimeType = mediaMimeType
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.mediaFileName = mediaFileName
        self.createdAt = createdAt
    }

    var hasImageAttachment: Bool {
        guard let mediaPath, !mediaPath.isEmpty,
              let mediaMimeType, mediaMimeType.hasPrefix("image/") else {
            return false
        }
        return true
    }

    var previewText: String {
        if !body.isEmpty { return body }
        if hasImageAttachment { return "사진" }
        return ""
    }

    var mediaFileExtension: String {
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

struct MessageReaction: Codable, Hashable, Identifiable {
    enum TargetKind: String, Codable {
        case chat
        case video
    }

    var targetKind: TargetKind
    var targetId: String
    var emoji: String
    var totalCount: Int
    var myReacted: Bool

    var id: String { "\(targetKind.rawValue):\(targetId):\(emoji)" }

    enum CodingKeys: String, CodingKey {
        case targetKind = "target_kind"
        case targetId = "target_id"
        case emoji
        case totalCount = "total_count"
        case myReacted = "my_reacted"
    }
}

enum TimelineItem: Identifiable, Hashable {
    case video(VideoMessage)
    case chat(ChatMessage)

    var id: String {
        switch self {
        case .video(let m): return "video:" + (m.id ?? UUID().uuidString)
        case .chat(let m): return "chat:" + (m.id ?? UUID().uuidString)
        }
    }

    var createdAt: Date? {
        switch self {
        case .video(let m): return m.createdAt
        case .chat(let m): return m.createdAt
        }
    }

    var senderUid: String {
        switch self {
        case .video(let m): return m.senderUid
        case .chat(let m): return m.senderUid
        }
    }
}
