import UserNotifications

/// Notification Service Extension: when a ping push arrives, download the 3s
/// clip from the short-lived signed URL in the payload and attach it so the
/// notification (iPhone and forwarded Apple Watch) shows a video thumbnail.
///
/// This target builds in Swift 5 language mode (see project.yml) — the standard
/// stored-handler extension pattern below trips a Swift 6 region-isolation
/// compiler limitation.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let best = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttempt = best

        guard let best,
              let urlString = request.content.userInfo["videoSignedUrl"] as? String,
              let url = URL(string: urlString) else {
            contentHandler(request.content)
            return
        }

        Task {
            if let attachment = await Self.downloadAttachment(from: url) {
                best.attachments = [attachment]
            }
            contentHandler(best)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt {
            contentHandler(bestAttempt)
        }
    }

    private static func downloadAttachment(from url: URL) async -> UNNotificationAttachment? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mp4")
            try data.write(to: tempURL)
            return try UNNotificationAttachment(identifier: "ping-video", url: tempURL, options: nil)
        } catch {
            return nil
        }
    }
}
