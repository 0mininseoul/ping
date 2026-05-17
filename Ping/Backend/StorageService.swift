@preconcurrency import FirebaseFirestore
import Foundation

@MainActor
final class StorageService {
    private let chunkSize = 512 * 1024
    private let maxChunkCount = 32
    private let maxBatchEncodedBytes = 7 * 1024 * 1024
    private let firestoreChunkScheme = "firestore-chunks://"

    private var db: Firestore { get throws { try FirebaseClient.shared.requireDB() } }

    func uploadVideo(
        localURL: URL,
        senderUid: String,
        messageId: String,
        authorizedUids: [String],
        expiresAt: Date
    ) async throws -> String {
        let data = try Data(contentsOf: localURL)
        guard !data.isEmpty else { throw PingError.invalidVideoPayload }

        let chunks = stride(from: 0, to: data.count, by: chunkSize).map { offset -> Data in
            Data(data[offset..<min(offset + chunkSize, data.count)])
        }
        guard chunks.count <= maxChunkCount else { throw PingError.videoPayloadTooLarge }

        let database = try db
        let manifestRef = database.collection("videoChunks").document(messageId)
        let uniqueAuthorizedUids = Array(Set(authorizedUids + [senderUid])).sorted()

        try await manifestRef.setData([
            "ownerUid": senderUid,
            "authorizedUids": uniqueAuthorizedUids,
            "chunkCount": chunks.count,
            "byteCount": data.count,
            "contentType": "video/mp4",
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": expiresAt
        ])

        let batchLimit = 400
        var batch = database.batch()
        var writes = 0
        var encodedBytes = 0

        for (index, chunk) in chunks.enumerated() {
            let encodedChunk = chunk.base64EncodedString()
            let encodedChunkBytes = encodedChunk.utf8.count

            if writes > 0 && (writes == batchLimit || encodedBytes + encodedChunkBytes > maxBatchEncodedBytes) {
                try await batch.commit()
                batch = database.batch()
                writes = 0
                encodedBytes = 0
            }

            let chunkRef = manifestRef.collection("chunks").document(String(format: "%04d", index))
            batch.setData([
                "ownerUid": senderUid,
                "authorizedUids": uniqueAuthorizedUids,
                "index": index,
                "data": encodedChunk,
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": expiresAt
            ], forDocument: chunkRef)
            writes += 1
            encodedBytes += encodedChunkBytes
        }

        if writes > 0 {
            try await batch.commit()
        }

        return "\(firestoreChunkScheme)\(senderUid)/\(messageId)"
    }

    func downloadVideo(from storageLocation: String, to localURL: URL) async throws {
        let videoId = try videoId(from: storageLocation)
        let database = try db
        let manifestRef = database.collection("videoChunks").document(videoId)
        let manifest = try await manifestRef.getDocument()
        guard let chunkCount = manifest.data()?["chunkCount"] as? Int else {
            throw PingError.invalidStorageURL
        }

        let snapshot = try await manifestRef.collection("chunks")
            .order(by: "index")
            .getDocuments()

        guard snapshot.documents.count == chunkCount else {
            throw PingError.invalidStorageURL
        }

        var output = Data()
        for document in snapshot.documents {
            guard let encoded = document.data()["data"] as? String,
                  let chunk = Data(base64Encoded: encoded) else {
                throw PingError.invalidStorageURL
            }
            output.append(chunk)
        }

        try output.write(to: localURL, options: .atomic)
    }

    private func videoId(from storageLocation: String) throws -> String {
        guard storageLocation.hasPrefix(firestoreChunkScheme) else {
            throw PingError.invalidStorageURL
        }

        let components = storageLocation
            .replacingOccurrences(of: firestoreChunkScheme, with: "")
            .split(separator: "/")
            .map(String.init)

        guard components.count == 2, !components[1].isEmpty else {
            throw PingError.invalidStorageURL
        }

        return components[1]
    }
}
