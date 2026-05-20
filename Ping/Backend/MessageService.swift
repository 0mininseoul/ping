import Foundation

@MainActor
final class MessageService {
    private let client: SupabaseClient
    private let storage: StorageService
    private let userService: UserService
    private let pollingIntervalNanoseconds: UInt64 = 2_000_000_000

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
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60)
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
                    "aspect_ratio_value": input.aspectRatio
                ])
            }
        }

        if sendableRooms.count == 1, let roomId = sendableRooms[0].id {
            try await userService.updateLastUsedRoom(uid: input.senderUid, roomId: roomId)
        }
    }

    func observeIncoming(uid: String) -> AsyncStream<VideoMessage> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var yieldedIds = Set<String>()

                while !Task.isCancelled {
                    do {
                        let messages: [VideoMessage] = try await client.rpcArray("ping_incoming_messages")
                        for message in messages.sorted(by: messageSort) {
                            guard let id = message.id, !yieldedIds.contains(id) else { continue }
                            yieldedIds.insert(id)
                            continuation.yield(message)
                        }
                    } catch {
                        NSLog("Incoming message polling failed: \(error)")
                    }

                    try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
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

    private func messageSort(lhs: VideoMessage, rhs: VideoMessage) -> Bool {
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
