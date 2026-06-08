import AppKit
import Foundation

@MainActor
final class HistoryCacheService {
    static let shared = HistoryCacheService()

    private let baseDir: URL
    private let maxBytes: Int64 = 500 * 1024 * 1024

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        baseDir = caches
            .appendingPathComponent("Ping", isDirectory: true)
            .appendingPathComponent("history-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func localURL(roomId: String, messageId: String) -> URL {
        let roomDir = baseDir.appendingPathComponent(roomId)
        try? FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
        return roomDir.appendingPathComponent("\(messageId).mp4")
    }

    func attachmentLocalURL(roomId: String, messageId: String, fileExtension: String) -> URL {
        let roomDir = baseDir.appendingPathComponent(roomId)
        try? FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
        let ext = fileExtension.isEmpty ? "img" : fileExtension
        return roomDir.appendingPathComponent("\(messageId)-attachment.\(ext)")
    }

    func thumbnailLocalURL(roomId: String, messageId: String) -> URL {
        let roomDir = baseDir.appendingPathComponent(roomId)
        try? FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
        return roomDir.appendingPathComponent("\(messageId)-thumbnail.jpg")
    }

    func cachedFile(roomId: String, messageId: String) -> URL? {
        let url = localURL(roomId: roomId, messageId: messageId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func cachedAttachmentFile(roomId: String, messageId: String, fileExtension: String) -> URL? {
        let url = attachmentLocalURL(roomId: roomId, messageId: messageId, fileExtension: fileExtension)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func cachedThumbnail(roomId: String, messageId: String) -> URL? {
        let url = thumbnailLocalURL(roomId: roomId, messageId: messageId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func cachedVideoMessageIds() -> Set<String> {
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: baseDir.path)) ?? []
        var ids = Set<String>()

        for subpath in files {
            let url = URL(fileURLWithPath: subpath)
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()

            if ext == "mp4", !name.isEmpty {
                ids.insert(name)
            } else if ext == "jpg", name.hasSuffix("-thumbnail") {
                let id = String(name.dropLast("-thumbnail".count))
                if !id.isEmpty {
                    ids.insert(id)
                }
            }
        }

        return ids
    }

    func storeDownload(roomId: String, messageId: String, sourceTemp: URL) throws -> URL {
        let dest = localURL(roomId: roomId, messageId: messageId)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: sourceTemp, to: dest)
        removeIfTemporaryFile(sourceTemp)
        Task { await evictIfNeeded() }
        return dest
    }

    func storeAttachmentDownload(
        roomId: String,
        messageId: String,
        fileExtension: String,
        sourceTemp: URL
    ) throws -> URL {
        let dest = attachmentLocalURL(
            roomId: roomId,
            messageId: messageId,
            fileExtension: fileExtension
        )
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: sourceTemp, to: dest)
        removeIfTemporaryFile(sourceTemp)
        Task { await evictIfNeeded() }
        return dest
    }

    func storeThumbnail(_ image: NSImage, roomId: String, messageId: String) throws -> URL {
        let dest = thumbnailLocalURL(roomId: roomId, messageId: messageId)
        guard let data = jpegData(for: image) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try? FileManager.default.removeItem(at: dest)
        try data.write(to: dest, options: .atomic)
        Task { await evictIfNeeded() }
        return dest
    }

    private func jpegData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }

    private func removeIfTemporaryFile(_ url: URL) {
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(tempRoot) else { return }

        try? FileManager.default.removeItem(at: url)
    }

    func evictIfNeeded() async {
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: baseDir.path)) ?? []
        var attrs: [(URL, Date, Int64)] = []
        for sub in files {
            let url = baseDir.appendingPathComponent(sub)
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = a[.size] as? Int64,
                  let mtime = a[.modificationDate] as? Date,
                  let type = a[.type] as? FileAttributeType,
                  type == .typeRegular else { continue }
            attrs.append((url, mtime, size))
        }

        let total = attrs.map(\.2).reduce(0, +)
        guard total > maxBytes else { return }

        let sorted = attrs.sorted { $0.1 < $1.1 }
        var remaining = total
        for (url, _, size) in sorted {
            if remaining <= maxBytes { break }
            try? FileManager.default.removeItem(at: url)
            remaining -= size
        }
    }

    func cleanupOlderThan(days: Int) async {
        let cutoff = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: baseDir.path)) ?? []
        for sub in files {
            let url = baseDir.appendingPathComponent(sub)
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let mtime = a[.modificationDate] as? Date else { continue }
            if mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
