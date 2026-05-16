import FirebaseFirestore
import Foundation

@MainActor
final class MessageService {
    private var db: Firestore { get throws { try FirebaseClient.shared.requireDB() } }
    private let storage = StorageService()
    private let userService = UserService()

    struct SendInput {
        let rooms: [Room]
        let localVideoURL: URL
        let mirrorPosition: MirrorPosition
        let senderUid: String
        let senderNickname: String
    }

    func send(_ input: SendInput) async throws {
        let fullRooms = input.rooms.filter { $0.memberUids.contains(input.senderUid) && $0.memberUids.count == 2 }
        guard !fullRooms.isEmpty else { throw PingError.noRecipients }

        let sharedVideoId = UUID().uuidString
        let videoURL = try await storage.uploadVideo(
            localURL: input.localVideoURL,
            senderUid: input.senderUid,
            messageId: sharedVideoId
        )

        let expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        let batch = try db.batch()

        for room in fullRooms {
            guard let roomId = room.id,
                  let receiverUid = room.memberUids.first(where: { $0 != input.senderUid }) else {
                continue
            }

            let docRef = try db.collection("messages").document()
            batch.setData([
                "roomId": roomId,
                "senderUid": input.senderUid,
                "receiverUid": receiverUid,
                "senderNickname": input.senderNickname,
                "videoUrl": videoURL,
                "durationMs": 2000,
                "mirrorPosition": [
                    "xRatio": input.mirrorPosition.xRatio,
                    "yRatio": input.mirrorPosition.yRatio
                ],
                "status": MessageStatus.uploaded.rawValue,
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": expiresAt
            ], forDocument: docRef)
        }

        try await batch.commit()

        if fullRooms.count == 1, let roomId = fullRooms[0].id {
            try await userService.updateLastUsedRoom(uid: input.senderUid, roomId: roomId)
        }
    }

    func observeIncoming(uid: String) -> AsyncStream<VideoMessage> {
        AsyncStream { continuation in
            Task { @MainActor in
                do {
                    let listener = try db.collection("messages")
                        .whereField("receiverUid", isEqualTo: uid)
                        .whereField("status", isEqualTo: MessageStatus.uploaded.rawValue)
                        .addSnapshotListener { snapshot, _ in
                            guard let changes = snapshot?.documentChanges else { return }
                            for change in changes where change.type == .added {
                                if let message = try? change.document.data(as: VideoMessage.self) {
                                    continuation.yield(message)
                                }
                            }
                        }
                    continuation.onTermination = { _ in listener.remove() }
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    func get(messageId: String) async throws -> VideoMessage? {
        let snapshot = try await db.collection("messages").document(messageId).getDocument()
        return try? snapshot.data(as: VideoMessage.self)
    }

    func markSeen(messageId: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "status": MessageStatus.seen.rawValue
        ])
    }
}
