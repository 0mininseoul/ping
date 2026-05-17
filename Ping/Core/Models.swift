import Foundation

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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case searchableName = "searchable_name"
        case ownerUid = "owner_uid"
        case memberUids = "member_uids"
        case memberNicknames = "member_nicknames"
        case status
        case createdAt = "created_at"
    }

    init(
        id: String? = nil,
        name: String,
        searchableName: String,
        ownerUid: String,
        memberUids: [String],
        memberNicknames: [String: String],
        status: RoomStatus,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.searchableName = searchableName
        self.ownerUid = ownerUid
        self.memberUids = memberUids
        self.memberNicknames = memberNicknames
        self.status = status
        self.createdAt = createdAt
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
