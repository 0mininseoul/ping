import FirebaseFirestore
import Foundation

@MainActor
final class RoomService {
    private var db: Firestore { get throws { try FirebaseClient.shared.requireDB() } }

    @discardableResult
    func createRoom(name: String, ownerUid: String, ownerNickname: String) async throws -> Room {
        let database = try db
        let ref = database.collection("rooms").document()
        let roomId = ref.documentID
        let searchable = SearchableText.normalize(name)

        try await ref.setData([
            "name": name,
            "searchableName": searchable,
            "ownerUid": ownerUid,
            "memberUids": [ownerUid],
            "memberNicknames": [ownerUid: ownerNickname],
            "status": RoomStatus.open.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ])

        try await database.collection("users").document(ownerUid).updateData([
            "rooms": FieldValue.arrayUnion([roomId]),
            "lastUsedRoomId": roomId
        ])

        return Room(
            id: roomId,
            name: name,
            searchableName: searchable,
            ownerUid: ownerUid,
            memberUids: [ownerUid],
            memberNicknames: [ownerUid: ownerNickname],
            status: .open
        )
    }

    func observeMyRooms(uid: String) -> AsyncStream<[Room]> {
        AsyncStream { continuation in
            Task { @MainActor in
                do {
                    let listener = try db.collection("rooms")
                        .whereField("memberUids", arrayContains: uid)
                        .addSnapshotListener { snapshot, _ in
                            let rooms = snapshot?.documents.compactMap { try? $0.data(as: Room.self) } ?? []
                            continuation.yield(rooms.sorted { $0.name < $1.name })
                        }
                    continuation.onTermination = { _ in listener.remove() }
                } catch {
                    continuation.yield([])
                    continuation.finish()
                }
            }
        }
    }

    func searchOpenRooms(prefix: String) async throws -> [Room] {
        let normalized = SearchableText.normalize(prefix)
        guard !normalized.isEmpty else { return [] }
        let end = normalized + "\u{f8ff}"

        let snapshot = try await db.collection("rooms")
            .whereField("status", isEqualTo: RoomStatus.open.rawValue)
            .whereField("searchableName", isGreaterThanOrEqualTo: normalized)
            .whereField("searchableName", isLessThan: end)
            .limit(to: 20)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: Room.self) }
    }

    func joinRoom(roomId: String, uid: String, nickname: String) async throws {
        let database = try db
        let roomRef = database.collection("rooms").document(roomId)

        _ = try await database.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(roomRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard var data = snapshot.data() else { return nil }
            var memberUids = data["memberUids"] as? [String] ?? []
            guard memberUids.count < 2 || memberUids.contains(uid) else { return nil }

            if !memberUids.contains(uid) {
                memberUids.append(uid)
            }

            var nicknames = data["memberNicknames"] as? [String: String] ?? [:]
            nicknames[uid] = nickname
            data["memberUids"] = memberUids
            data["memberNicknames"] = nicknames
            data["status"] = memberUids.count == 2 ? RoomStatus.full.rawValue : RoomStatus.open.rawValue

            transaction.setData(data, forDocument: roomRef)
            return nil
        }

        try await database.collection("users").document(uid).updateData([
            "rooms": FieldValue.arrayUnion([roomId]),
            "lastUsedRoomId": roomId
        ])
    }

    func leaveRoom(roomId: String, uid: String) async throws {
        let database = try db
        let roomRef = database.collection("rooms").document(roomId)

        _ = try await database.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(roomRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard var data = snapshot.data() else { return nil }
            let memberUids = (data["memberUids"] as? [String] ?? []).filter { $0 != uid }
            var nicknames = data["memberNicknames"] as? [String: String] ?? [:]
            nicknames.removeValue(forKey: uid)

            data["memberUids"] = memberUids
            data["memberNicknames"] = nicknames
            data["status"] = memberUids.count < 2 ? RoomStatus.open.rawValue : RoomStatus.full.rawValue

            transaction.setData(data, forDocument: roomRef)
            return nil
        }

        try await database.collection("users").document(uid).updateData([
            "rooms": FieldValue.arrayRemove([roomId])
        ])
    }

    func renameRoom(roomId: String, newName: String) async throws {
        try await db.collection("rooms").document(roomId).updateData([
            "name": newName,
            "searchableName": SearchableText.normalize(newName)
        ])
    }
}
