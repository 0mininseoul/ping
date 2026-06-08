import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class StorageService {
    static let bucket = "ping-videos"
    static let mediaBucket = "ping-media"
    private let maxVideoBytes = 50 * 1024 * 1024
    private let maxImageBytes = 15 * 1024 * 1024
    private static let maxDownloadCacheBytes: Int64 = 500 * 1024 * 1024

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

    static func cachedDownloadURL(remotePath: String) -> URL {
        downloadCacheDirectory()
            .appendingPathComponent(cacheFileName(remotePath: remotePath, fallbackExtension: "mp4"))
    }

    static func cachedChatMediaURL(remotePath: String, fileExtension: String) -> URL {
        downloadCacheDirectory()
            .appendingPathComponent(cacheFileName(remotePath: remotePath, fallbackExtension: fileExtension))
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

        let cachedURL = Self.cachedDownloadURL(remotePath: storageLocation)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            try copyCachedFile(from: cachedURL, to: localURL)
            return
        }

        let tempURL = localURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(localURL.lastPathComponent).\(UUID().uuidString).tmp")
        try FileManager.default.createDirectory(
            at: tempURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await client.downloadObject(
            bucket: Self.bucket,
            path: storageLocation,
            to: tempURL
        )
        try replaceItem(at: localURL, with: tempURL)
        try copyCachedFile(from: localURL, to: cachedURL)
        Task { await Self.evictDownloadCacheIfNeeded() }
    }

    func downloadVideo(remotePath: String) async throws -> URL {
        guard !remotePath.isEmpty, remotePath.hasSuffix(".mp4") else {
            throw PingError.invalidStorageURL
        }

        let cachedURL = Self.cachedDownloadURL(remotePath: remotePath)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        let tempURL = cachedURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(cachedURL.lastPathComponent).\(UUID().uuidString).tmp")
        try await client.downloadObject(
            bucket: Self.bucket,
            path: remotePath,
            to: tempURL
        )
        try replaceItem(at: cachedURL, with: tempURL)
        Task { await Self.evictDownloadCacheIfNeeded() }
        return cachedURL
    }

    func deleteVideo(remotePath: String) async throws {
        guard !remotePath.isEmpty, remotePath.hasSuffix(".mp4") else {
            throw PingError.invalidStorageURL
        }

        try await client.deleteObject(bucket: Self.bucket, path: remotePath)
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

        let cachedURL = Self.cachedChatMediaURL(remotePath: remotePath, fileExtension: fileExtension)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        let tempURL = cachedURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(cachedURL.lastPathComponent).\(UUID().uuidString).tmp")
        try await client.downloadObject(
            bucket: Self.mediaBucket,
            path: remotePath,
            to: tempURL
        )
        try replaceItem(at: cachedURL, with: tempURL)
        Task { await Self.evictDownloadCacheIfNeeded() }
        return cachedURL
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func copyCachedFile(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if source.standardizedFileURL == destination.standardizedFileURL {
            return
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func downloadCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = caches
            .appendingPathComponent("Ping", isDirectory: true)
            .appendingPathComponent("storage-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func cacheFileName(remotePath: String, fallbackExtension: String) -> String {
        let sanitized = remotePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let fileName = sanitized.isEmpty ? UUID().uuidString : String(sanitized)
        if fileName.contains(".") {
            return fileName
        }

        let ext = fallbackExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ext.isEmpty ? fileName : "\(fileName).\(ext)"
    }

    private static func evictDownloadCacheIfNeeded() async {
        let directory = downloadCacheDirectory()
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: directory.path)) ?? []
        var attrs: [(URL, Date, Int64)] = []
        for sub in files {
            let url = directory.appendingPathComponent(sub)
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = a[.size] as? Int64,
                  let mtime = a[.modificationDate] as? Date,
                  let type = a[.type] as? FileAttributeType,
                  type == .typeRegular else { continue }
            attrs.append((url, mtime, size))
        }

        let total = attrs.map(\.2).reduce(0, +)
        guard total > maxDownloadCacheBytes else { return }

        let sorted = attrs.sorted { $0.1 < $1.1 }
        var remaining = total
        for (url, _, size) in sorted {
            if remaining <= maxDownloadCacheBytes { break }
            try? FileManager.default.removeItem(at: url)
            remaining -= size
        }
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
