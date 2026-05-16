import FirebaseStorage
import FirebaseCore
import Foundation

@MainActor
final class StorageService {
    func uploadVideo(localURL: URL, senderUid: String, messageId: String) async throws -> String {
        let path = videoPath(senderUid: senderUid, messageId: messageId)
        let ref = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        _ = try await ref.putFileAsync(from: localURL, metadata: metadata)
        return try storageURL(forPath: path)
    }

    func downloadVideo(from storageLocation: String, to localURL: URL) async throws {
        let ref = try storageReference(for: storageLocation)
        _ = try await ref.writeAsync(toFile: localURL)
    }

    private func videoPath(senderUid: String, messageId: String) -> String {
        "videos/\(senderUid)/\(messageId).mp4"
    }

    private func storageReference(for storageLocation: String) throws -> StorageReference {
        if storageLocation.hasPrefix("gs://") {
            guard URL(string: storageLocation) != nil else { throw PingError.invalidStorageURL }
            return storage.reference(forURL: storageLocation)
        }

        guard storageLocation.hasPrefix("videos/") else { throw PingError.invalidStorageURL }
        return storage.reference(withPath: storageLocation)
    }

    private func storageURL(forPath path: String) throws -> String {
        guard let bucket = FirebaseApp.app()?.options.storageBucket, !bucket.isEmpty else {
            throw PingError.invalidStorageURL
        }
        return "gs://\(bucket)/\(path)"
    }

    private var storage: Storage {
        Storage.storage()
    }
}
