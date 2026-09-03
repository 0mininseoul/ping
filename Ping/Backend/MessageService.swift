import Foundation
import OSLog

private let signposter = OSSignposter(subsystem: "com.youngminpark.ping.Ping", category: "polling")

@MainActor
final class MessageService {
    private let client: SupabaseClient
    private let storage: StorageService
    private let userService: UserService

    enum VideoRemovalResult: String, Decodable {
        case deletedForEveryone = "deleted"
        case hiddenForCurrentUser = "hidden"
        case missing
    }

    init(
        client: SupabaseClient = .shared,
        storage: StorageService = StorageService(),
        userService: UserService = UserService()
    ) {
        self.client = client
        self.storage = storage
        self.userService = userService
    }

    struct SendInput {
        let rooms: [Room]
        let localVideoURL: URL
        let mirrorPosition: MirrorPosition
        let senderUid: String
        let senderNickname: String
        let captureMode: CaptureMode
        let aspectRatio: Double
        let allowsLocalSave: Bool
    }

    func send(_ input: SendInput) async throws {
        let sendableRooms = input.rooms.filter {
            $0.memberUids.contains(input.senderUid)
                && $0.memberUids.count >= RoomLimits.minSendableMembers
        }
        guard !sendableRooms.isEmpty else { throw PingError.noRecipients }

        let sharedVideoId = UUID().uuidString
        let authorizedReceiverUids = Array(Set(sendableRooms.flatMap { room in
            room.memberUids.filter { $0 != input.senderUid }
        })).sorted()
        let expiresAt = Date().addingTimeInterval(30 * 24 * 60 * 60)
        let videoStoragePath = try await storage.uploadVideo(
            localURL: input.localVideoURL,
            senderUid: input.senderUid,
            messageId: sharedVideoId,
            authorizedUids: authorizedReceiverUids,
            expiresAt: expiresAt
        )

        for room in sendableRooms {
            guard let roomId = room.id else {
                continue
            }

            let receiverUids = room.memberUids.filter { $0 != input.senderUid }

            for receiverUid in receiverUids {
                let _: String = try await client.rpcValue("ping_create_message", body: [
                    "room_uuid": roomId,
                    "receiver_uid": receiverUid,
                    "sender_nickname_text": input.senderNickname,
                    "video_id_text": sharedVideoId,
                    "video_url_text": videoStoragePath,
                    "x_ratio": input.mirrorPosition.xRatio,
                    "y_ratio": input.mirrorPosition.yRatio,
                    "capture_mode_text": input.captureMode.rawValue,
                    "aspect_ratio_value": input.aspectRatio,
                    "allows_local_save_value": input.allowsLocalSave
                ])
            }
        }

        if sendableRooms.count == 1, let roomId = sendableRooms[0].id {
            try await userService.updateLastUsedRoom(uid: input.senderUid, roomId: roomId)
        }
    }

    /// Realtime 신호를 받았을 때 폴링 주기를 기다리지 않고 한 번 읽는다.
    func incomingMessages() async throws -> [VideoMessage] {
        let messages: [VideoMessage] = try await client.rpcArray("ping_incoming_messages")
        return messages.sorted(by: Self.messageSortStatic)
    }

    func observeIncoming(uid: String) -> AsyncStream<VideoMessage> {
        let client = self.client
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                var yieldedIds = Set<String>()

                while !Task.isCancelled {
                    let intervalState = signposter.beginInterval("messages-poll-cycle")
                    do {
                        let messages: [VideoMessage] = try await client.rpcArray("ping_incoming_messages")
                        for message in messages.sorted(by: Self.messageSortStatic) {
                            guard let id = message.id, !yieldedIds.contains(id) else { continue }
                            yieldedIds.insert(id)
                            continuation.yield(message)
                        }
                    } catch {
                        NSLog("Incoming message polling failed: \(error)")
                    }
                    signposter.endInterval("messages-poll-cycle", intervalState)
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func get(messageId: String) async throws -> VideoMessage? {
        let messages: [VideoMessage] = try await client.rpcArray("ping_get_message", body: [
            "message_uuid": messageId
        ])
        return messages.first
    }

    func markSeen(messageId: String) async throws {
        try await client.rpcVoid("ping_mark_message_seen", body: [
            "message_uuid": messageId
        ])
    }

    func markNotified(messageId: String) async throws {
        try await client.rpcVoid("ping_mark_message_notified", body: [
            "message_uuid": messageId
        ])
    }

    func roomMessages(roomId: String, beforeTimestamp: Date? = nil, limit: Int = 50) async throws -> [VideoMessage] {
        var body: [String: Any] = [
            "room_uuid": roomId,
            "page_limit": limit
        ]
        if let beforeTimestamp {
            body["before_ts"] = ISO8601DateFormatter.shared.string(from: beforeTimestamp)
        }
        return try await client.rpcArray("ping_room_messages", body: body)
    }

    func deleteMessage(messageId: String) async throws {
        try await client.rpcVoid("ping_delete_message", body: ["message_uuid": messageId])
    }

    func removeMessageForCurrentUser(messageId: String) async throws -> VideoRemovalResult {
        let rawResult: String = try await client.rpcValue("ping_remove_video_message", body: [
            "message_uuid": messageId
        ])
        guard let result = VideoRemovalResult(rawValue: rawResult) else {
            throw PingError.supabaseRequestFailed(statusCode: 200, message: "Unexpected delete result: \(rawResult)")
        }
        return result
    }

    func hideMessageForReceiver(messageId: String) async throws {
        try await client.rpcVoid("ping_hide_message_for_receiver", body: ["message_uuid": messageId])
    }

    private func messageSort(lhs: VideoMessage, rhs: VideoMessage) -> Bool {
        Self.messageSortStatic(lhs: lhs, rhs: rhs)
    }

    private nonisolated static func messageSortStatic(lhs: VideoMessage, rhs: VideoMessage) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return false
        case (.none, .some):
            return true
        case (.none, .none):
            return (lhs.id ?? "") < (rhs.id ?? "")
        }
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
