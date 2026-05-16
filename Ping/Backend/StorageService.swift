import FirebaseStorage
import Foundation

@MainActor
final class StorageService {
    private let storage = Storage.storage()

    func uploadVideo(localURL: URL, senderUid: String, messageId: String) async throws -> String {
        let ref = storage.reference(withPath: "videos/\(senderUid)/\(messageId).mp4")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        _ = try await ref.putFileAsync(from: localURL, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    func downloadVideo(from urlString: String, to localURL: URL) async throws {
        guard let url = URL(string: urlString) else { throw PingError.invalidStorageURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        try data.write(to: localURL, options: .atomic)
    }
}
