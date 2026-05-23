import Foundation

enum LocalArchive {
    enum Direction {
        case sent
        case received
    }

    static let localSaveEnabledKey = "ping.storage.localSaveEnabled"
    static let saveSentEnabledKey = "ping.storage.saveSentEnabled"
    static let saveReceivedEnabledKey = "ping.storage.saveReceivedEnabled"
    static let autoDeleteAfter30DaysKey = "ping.storage.autoDeleteAfter30Days"

    private static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    static var localSaveEnabled: Bool {
        get {
            migrateLegacyPreferencesIfNeeded()
            return saveSentEnabled || saveReceivedEnabled
        }
        set {
            UserDefaults.standard.set(newValue, forKey: localSaveEnabledKey)
            UserDefaults.standard.set(newValue, forKey: saveSentEnabledKey)
            UserDefaults.standard.set(newValue, forKey: saveReceivedEnabledKey)
        }
    }

    static var saveSentEnabled: Bool {
        get {
            migrateLegacyPreferencesIfNeeded()
            return UserDefaults.standard.bool(forKey: saveSentEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: saveSentEnabledKey)
            UserDefaults.standard.set(saveSentEnabled || saveReceivedEnabled, forKey: localSaveEnabledKey)
        }
    }

    static var saveReceivedEnabled: Bool {
        get {
            migrateLegacyPreferencesIfNeeded()
            return UserDefaults.standard.bool(forKey: saveReceivedEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: saveReceivedEnabledKey)
            UserDefaults.standard.set(saveSentEnabled || saveReceivedEnabled, forKey: localSaveEnabledKey)
        }
    }

    static var autoDeleteAfter30Days: Bool {
        get {
            UserDefaults.standard.bool(forKey: autoDeleteAfter30DaysKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoDeleteAfter30DaysKey)
            if newValue {
                deleteExpiredFilesIfNeeded(force: true)
            }
        }
    }

    static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyValue = defaults.object(forKey: localSaveEnabledKey) as? Bool ?? true

        if defaults.object(forKey: saveSentEnabledKey) == nil {
            defaults.set(legacyValue, forKey: saveSentEnabledKey)
        }

        if defaults.object(forKey: saveReceivedEnabledKey) == nil {
            defaults.set(legacyValue, forKey: saveReceivedEnabledKey)
        }

        if defaults.object(forKey: localSaveEnabledKey) == nil {
            defaults.set(legacyValue, forKey: localSaveEnabledKey)
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
        migrateLegacyPreferencesIfNeeded()
        let sent = documentsRoot().appendingPathComponent("sent", isDirectory: true)
        let received = documentsRoot().appendingPathComponent("received", isDirectory: true)
        try? FileManager.default.createDirectory(at: sent, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        deleteExpiredFilesIfNeeded()
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

    static func existingVideoURL(
        direction: Direction,
        nickname: String,
        date: Date,
        tolerance: TimeInterval = 30
    ) -> URL? {
        let exactURL: URL
        let folderName: String
        let marker: String

        switch direction {
        case .sent:
            exactURL = sentURL(to: nickname, date: date)
            folderName = "sent"
            marker = "_to_"
        case .received:
            exactURL = receivedURL(from: nickname, date: date)
            folderName = "received"
            marker = "_from_"
        }

        if FileManager.default.fileExists(atPath: exactURL.path) {
            return exactURL
        }

        let folder = documentsRoot().appendingPathComponent(folderName, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let expectedSuffix = "\(marker)\(safeFileComponent(nickname)).mp4".precomposedStringWithCanonicalMapping
        let candidates = files.compactMap { file -> (URL, TimeInterval)? in
            let name = file.lastPathComponent.precomposedStringWithCanonicalMapping
            guard name.hasSuffix(expectedSuffix),
                  let fileDate = dateFromFileName(name) else {
                return nil
            }

            let distance = abs(fileDate.timeIntervalSince(date))
            guard distance <= tolerance else { return nil }
            return (file, distance)
        }

        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    static func deleteExpiredFilesIfNeeded(now: Date = Date(), force: Bool = false) {
        guard force || autoDeleteAfter30Days else { return }

        let cutoff = now.addingTimeInterval(-retentionInterval)
        let folders = [
            documentsRoot().appendingPathComponent("sent", isDirectory: true),
            documentsRoot().appendingPathComponent("received", isDirectory: true)
        ]

        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for file in files where file.pathExtension.lowercased() == "mp4" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let date = values?.contentModificationDate ?? values?.creationDate ?? .distantFuture
                if date < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private static func dateFromFileName(_ name: String) -> Date? {
        guard name.count >= 19 else { return nil }
        let prefix = String(name.prefix(19))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.date(from: prefix)
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
