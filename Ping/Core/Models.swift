import Foundation
@preconcurrency import FirebaseFirestore

struct MirrorPosition: Codable, Equatable, Hashable {
    var xRatio: Double
    var yRatio: Double
}

struct PingUser: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var nickname: String
    var searchableNickname: String
    var rooms: [String]
    var lastUsedRoomId: String?
    @ServerTimestamp var createdAt: Date?

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
    @DocumentID var id: String?
    var name: String
    var searchableName: String
    var ownerUid: String
    var memberUids: [String]
    var memberNicknames: [String: String]
    var status: RoomStatus
    @ServerTimestamp var createdAt: Date?

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
    @DocumentID var id: String?
    var roomId: String
    var senderUid: String
    var receiverUid: String
    var senderNickname: String
    var videoId: String
    var videoUrl: String
    var durationMs: Int
    var mirrorPosition: MirrorPosition
    var status: MessageStatus
    @ServerTimestamp var createdAt: Date?
    var expiresAt: Date
}

enum MessageStatus: String, Codable, Hashable {
    case uploaded
    case seen
}

struct Invitation: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var fromUid: String
    var toUid: String
    var roomId: String
    var fromNickname: String
    var roomName: String
    @ServerTimestamp var createdAt: Date?
    var expiresAt: Date
}
