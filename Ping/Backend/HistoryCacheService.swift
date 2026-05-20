import Foundation

@MainActor
final class HistoryCacheService {
    static let shared = HistoryCacheService()

    private let baseDir: URL
    private let maxBytes: Int64 = 500 * 1024 * 1024

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseDir = docs.appendingPathComponent("Ping/cache")
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func localURL(roomId: String, messageId: String) -> URL {
        let roomDir = baseDir.appendingPathComponent(roomId)
        try? FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
        return roomDir.appendingPathComponent("\(messageId).mp4")
    }

    func cachedFile(roomId: String, messageId: String) -> URL? {
        let url = localURL(roomId: roomId, messageId: messageId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func storeDownload(roomId: String, messageId: String, sourceTemp: URL) throws -> URL {
        let dest = localURL(roomId: roomId, messageId: messageId)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: sourceTemp, to: dest)
        Task { await evictIfNeeded() }
        return dest
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
