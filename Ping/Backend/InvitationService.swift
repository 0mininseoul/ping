import FirebaseFirestore
import Foundation

@MainActor
final class InvitationService {
    private var db: Firestore { get throws { try FirebaseClient.shared.requireDB() } }

    func send(fromUid: String, fromNickname: String, toUid: String, roomId: String, roomName: String) async throws {
        let ref = try db.collection("invitations").document()
        try await ref.setData([
            "fromUid": fromUid,
            "toUid": toUid,
            "roomId": roomId,
            "fromNickname": fromNickname,
            "roomName": roomName,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(7 * 24 * 60 * 60)
        ])
    }

    func observeIncoming(uid: String) -> AsyncStream<[Invitation]> {
        AsyncStream { continuation in
            Task { @MainActor in
                do {
                    let listener = try db.collection("invitations")
                        .whereField("toUid", isEqualTo: uid)
                        .addSnapshotListener { snapshot, _ in
                            let invites = snapshot?.documents.compactMap { try? $0.data(as: Invitation.self) } ?? []
                            continuation.yield(invites)
                        }
                    continuation.onTermination = { _ in listener.remove() }
                } catch {
                    continuation.yield([])
                    continuation.finish()
                }
            }
        }
    }

    func accept(invitation: Invitation, myUid: String, myNickname: String, roomService: RoomService) async throws {
        try await roomService.joinRoom(roomId: invitation.roomId, uid: myUid, nickname: myNickname)
        if let inviteId = invitation.id {
            try await db.collection("invitations").document(inviteId).delete()
        }
    }

    func reject(inviteId: String) async throws {
        try await db.collection("invitations").document(inviteId).delete()
    }
}
