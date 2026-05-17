@preconcurrency import FirebaseFirestore
import Foundation

@MainActor
final class UserService {
    private var db: Firestore { get throws { try FirebaseClient.shared.requireDB() } }

    func upsert(uid: String, nickname: String) async throws {
        try await db.collection("users").document(uid).setData([
            "nickname": nickname,
            "searchableNickname": SearchableText.normalize(nickname),
            "rooms": FieldValue.arrayUnion([]),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func get(uid: String) async throws -> PingUser? {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        return try? snapshot.data(as: PingUser.self)
    }

    func searchByNicknamePrefix(_ prefix: String, excluding excludeUid: String?) async throws -> [PingUser] {
        let normalized = SearchableText.normalize(prefix)
        guard !normalized.isEmpty else { return [] }

        let end = normalized + "\u{f8ff}"
        let snapshot = try await db.collection("users")
            .whereField("searchableNickname", isGreaterThanOrEqualTo: normalized)
            .whereField("searchableNickname", isLessThan: end)
            .limit(to: 20)
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: PingUser.self) }
            .filter { $0.id != excludeUid }
    }

    func updateLastUsedRoom(uid: String, roomId: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "lastUsedRoomId": roomId
        ])
    }
}
