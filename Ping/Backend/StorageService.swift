import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class StorageService {
    static let bucket = "ping-videos"
    static let mediaBucket = "ping-media"
    private let maxVideoBytes = 50 * 1024 * 1024
    private let maxImageBytes = 15 * 1024 * 1024

    private let client: SupabaseClient

    struct ChatImageUpload: Hashable {
        let path: String
        let mimeType: String
        let width: Int?
        let height: Int?
        let fileName: String?
    }

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    nonisolated static func videoObjectPath(senderUid: String, videoId: String) -> String {
        "\(senderUid)/\(videoId).mp4"
    }

    nonisolated static func chatImageObjectPath(
        senderUid: String,
        messageId: String,
        fileExtension: String
    ) -> String {
        "\(senderUid)/chat-images/\(messageId).\(fileExtension)"
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

    func downloadVideo(remotePath: String) async throws -> URL {
        guard !remotePath.isEmpty, remotePath.hasSuffix(".mp4") else {
            throw PingError.invalidStorageURL
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-dl-\(UUID().uuidString).mp4")
        try await client.downloadObject(
            bucket: Self.bucket,
            path: remotePath,
            to: tempURL
        )
        return tempURL
    }

    func uploadChatImage(
        localURL: URL,
        senderUid: String,
        messageId: String
    ) async throws -> ChatImageUpload {
        let didAccess = localURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try localURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize, fileSize > 0 else {
            throw PingError.invalidImagePayload
        }
        guard fileSize <= maxImageBytes else {
            throw PingError.imagePayloadTooLarge
        }

        let content = try imageContent(localURL: localURL)
        let path = Self.chatImageObjectPath(
            senderUid: senderUid,
            messageId: messageId,
            fileExtension: content.fileExtension
        )

        try await client.uploadObject(
            bucket: Self.mediaBucket,
            path: path,
            localURL: localURL,
            contentType: content.mimeType
        )

        let pixelSize = imagePixelSize(localURL: localURL)
        return ChatImageUpload(
            path: path,
            mimeType: content.mimeType,
            width: pixelSize?.width,
            height: pixelSize?.height,
            fileName: localURL.lastPathComponent
        )
    }

    func downloadChatMedia(remotePath: String, fileExtension: String) async throws -> URL {
        guard !remotePath.isEmpty,
              remotePath.contains("/chat-images/"),
              !fileExtension.isEmpty else {
            throw PingError.invalidStorageURL
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-media-\(UUID().uuidString).\(fileExtension)")
        try await client.downloadObject(
            bucket: Self.mediaBucket,
            path: remotePath,
            to: tempURL
        )
        return tempURL
    }

    private func imageContent(localURL: URL) throws -> (mimeType: String, fileExtension: String) {
        let ext = localURL.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return ("image/jpeg", "jpg")
        case "png":
            return ("image/png", "png")
        case "heic":
            return ("image/heic", "heic")
        case "heif":
            return ("image/heif", "heif")
        case "gif":
            return ("image/gif", "gif")
        case "webp":
            return ("image/webp", "webp")
        default:
            guard let type = UTType(filenameExtension: ext),
                  type.conforms(to: .image),
                  let mimeType = type.preferredMIMEType else {
                throw PingError.invalidImagePayload
            }
            return (mimeType, ext.isEmpty ? "img" : ext)
        }
    }

    private func imagePixelSize(localURL: URL) -> (width: Int, height: Int)? {
        guard let image = NSImage(contentsOf: localURL) else { return nil }
        let representations = image.representations.filter {
            $0.pixelsWide > 0 && $0.pixelsHigh > 0
        }
        guard let best = representations.max(by: { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }) else {
            return nil
        }
        return (best.pixelsWide, best.pixelsHigh)
    }
}
