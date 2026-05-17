@preconcurrency import FirebaseFirestore
import Foundation

@MainActor
final class CleanupService {
    private let queryLimit = 100
    private let expiredVideoLimit = 25
    private let batchLimit = 450
    private let expirationSafetyDelay: TimeInterval = 5 * 60

    private var db: Firestore { get throws { try FirebaseClient.shared.requireDB() } }

    func run(uid: String) async throws {
        try await deleteExpiredMessages(uid: uid)
        try await deleteExpiredInvitations(uid: uid)
        try await deleteExpiredVideos(uid: uid)
    }

    private func deleteExpiredMessages(uid: String) async throws {
        let database = try db
        var refsByPath: [String: DocumentReference] = [:]
        let cutoff = cleanupCutoff()

        for ownerField in ["senderUid", "receiverUid"] {
            let snapshot = try await database.collection("messages")
                .whereField(ownerField, isEqualTo: uid)
                .whereField("expiresAt", isLessThan: cutoff)
                .limit(to: queryLimit)
                .getDocuments()

            for document in snapshot.documents {
                refsByPath[document.reference.path] = document.reference
            }
        }

        try await delete(Array(refsByPath.values), database: database)
    }

    private func deleteExpiredInvitations(uid: String) async throws {
        let database = try db
        var refsByPath: [String: DocumentReference] = [:]
        let cutoff = cleanupCutoff()

        for ownerField in ["toUid", "fromUid"] {
            let snapshot = try await database.collection("invitations")
                .whereField(ownerField, isEqualTo: uid)
                .whereField("expiresAt", isLessThan: cutoff)
                .limit(to: queryLimit)
                .getDocuments()

            for document in snapshot.documents {
                refsByPath[document.reference.path] = document.reference
            }
        }

        try await delete(Array(refsByPath.values), database: database)
    }

    private func deleteExpiredVideos(uid: String) async throws {
        let database = try db
        let cutoff = cleanupCutoff()
        let chunkSnapshot = try await database.collectionGroup("chunks")
            .whereField("authorizedUids", arrayContains: uid)
            .whereField("expiresAt", isLessThan: cutoff)
            .limit(to: queryLimit)
            .getDocuments()
        try await delete(chunkSnapshot.documents.map(\.reference), database: database)

        let manifestSnapshot = try await database.collection("videoChunks")
            .whereField("authorizedUids", arrayContains: uid)
            .whereField("expiresAt", isLessThan: cutoff)
            .limit(to: expiredVideoLimit)
            .getDocuments()
        try await delete(manifestSnapshot.documents.map(\.reference), database: database)
    }

    private func delete(_ refs: [DocumentReference], database: Firestore) async throws {
        guard !refs.isEmpty else { return }

        var batch = database.batch()
        var writes = 0

        for ref in refs {
            batch.deleteDocument(ref)
            writes += 1

            if writes == batchLimit {
                try await batch.commit()
                batch = database.batch()
                writes = 0
            }
        }

        if writes > 0 {
            try await batch.commit()
        }
    }

    private func cleanupCutoff() -> Date {
        Date().addingTimeInterval(-expirationSafetyDelay)
    }
}
