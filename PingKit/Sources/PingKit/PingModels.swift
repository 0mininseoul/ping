import Foundation

/// A 3-second video message, decoded from `ping_get_message` /
/// `ping_incoming_messages`. Only the fields the iOS/watch receive flow needs
/// are modeled; extra columns in the RPC payload are ignored.
public struct VideoMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let roomId: String
    public let senderUid: String
    public let receiverUid: String
    public let senderNickname: String
    public let videoId: String
    public let videoUrl: String
    public let durationMs: Int
    public let status: String
    public let createdAt: Date
    public let captureMode: String?
    public let aspectRatio: Double?

    enum CodingKeys: String, CodingKey {
        case id, status
        case roomId = "room_id"
        case senderUid = "sender_uid"
        case receiverUid = "receiver_uid"
        case senderNickname = "sender_nickname"
        case videoId = "video_id"
        case videoUrl = "video_url"
        case durationMs = "duration_ms"
        case createdAt = "created_at"
        case captureMode = "capture_mode"
        case aspectRatio = "aspect_ratio"
    }

    /// Storage object path inside the `ping-videos` bucket: `<senderUid>/<videoId>.mp4`.
    public var storagePath: String { "\(senderUid)/\(videoId).mp4" }

    static func dedupedSenderRows(_ messages: [VideoMessage], currentUid: String?) -> [VideoMessage] {
        guard let currentUid else { return messages }

        var seenSenderVideos = Set<String>()
        var deduped: [VideoMessage] = []
        for message in messages {
            guard message.senderUid == currentUid else {
                deduped.append(message)
                continue
            }

            let key = "\(message.roomId)|\(message.videoUrl)"
            guard seenSenderVideos.insert(key).inserted else { continue }
            deduped.append(message)
        }
        return deduped
    }
}
