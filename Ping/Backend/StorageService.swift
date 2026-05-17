import Foundation

@MainActor
final class StorageService {
    static let bucket = "ping-videos"
    private let maxVideoBytes = 50 * 1024 * 1024

    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    nonisolated static func videoObjectPath(senderUid: String, videoId: String) -> String {
        "\(senderUid)/\(videoId).mp4"
    }

    func uploadVideo(
        localURL: URL,
        senderUid: String,
        messageId: String,
        authorizedUids: [String],
        expiresAt: Date
    ) async throws -> String {
        let resourceValues = try localURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize, fileSize > 0 else {
            throw PingError.invalidVideoPayload
        }
        guard fileSize <= maxVideoBytes else {
            throw PingError.videoPayloadTooLarge
        }

        let path = Self.videoObjectPath(senderUid: senderUid, videoId: messageId)
        try await client.uploadObject(
            bucket: Self.bucket,
            path: path,
            localURL: localURL,
            contentType: "video/mp4"
        )
        return path
    }

    func downloadVideo(from storageLocation: String, to localURL: URL) async throws {
        guard !storageLocation.isEmpty, storageLocation.hasSuffix(".mp4") else {
            throw PingError.invalidStorageURL
        }

        try await client.downloadObject(
            bucket: Self.bucket,
            path: storageLocation,
            to: localURL
        )
    }
}
