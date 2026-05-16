import Foundation

enum LocalArchive {
    static func documentsRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Ping", isDirectory: true)
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
}
