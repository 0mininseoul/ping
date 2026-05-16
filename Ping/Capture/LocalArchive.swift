import Foundation

enum LocalArchive {
    static let localSaveEnabledKey = "ping.storage.localSaveEnabled"

    static var localSaveEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: localSaveEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: localSaveEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: localSaveEnabledKey)
        }
    }

    static func documentsRoot() -> URL {
        let preferred = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Ping", isDirectory: true)

        if canUseDirectory(preferred) {
            return preferred
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Ping", isDirectory: true)
    }

    static func ensureFolders() {
        let sent = documentsRoot().appendingPathComponent("sent", isDirectory: true)
        let received = documentsRoot().appendingPathComponent("received", isDirectory: true)
        try? FileManager.default.createDirectory(at: sent, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
    }

    static func sentURL(to nickname: String, date: Date = Date()) -> URL {
        documentsRoot()
            .appendingPathComponent("sent", isDirectory: true)
            .appendingPathComponent("\(timestamp(date))_to_\(safeFileComponent(nickname)).mp4")
    }

    static func receivedURL(from nickname: String, date: Date = Date()) -> URL {
        documentsRoot()
            .appendingPathComponent("received", isDirectory: true)
            .appendingPathComponent("\(timestamp(date))_from_\(safeFileComponent(nickname)).mp4")
    }

    static func allPartnersSentURL(date: Date = Date()) -> URL {
        documentsRoot()
            .appendingPathComponent("sent", isDirectory: true)
            .appendingPathComponent("\(timestamp(date))_to_all.mp4")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private static func safeFileComponent(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: illegal).joined(separator: "_")
    }

    private static func canUseDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
