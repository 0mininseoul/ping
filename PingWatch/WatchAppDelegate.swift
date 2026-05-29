import WatchKit
import UserNotifications

/// Activates WatchConnectivity, registers the reply notification category, and
/// handles the inline dictation reply + tap-to-play routing.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionStore.shared.activate()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: "PING_REPLY",
            title: "답장",
            options: [],
            textInputButtonTitle: "보내기",
            textInputPlaceholder: "메시지"
        )
        let category = UNNotificationCategory(
            identifier: "PING_MESSAGE",
            actions: [reply],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let messageId = userInfo["messageId"] as? String
        let roomId = userInfo["roomId"] as? String

        if let textResponse = response as? UNTextInputNotificationResponse {
            let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let roomId, !text.isEmpty, let client = await WatchSessionStore.shared.makeClient() {
                try? await client.sendChat(roomId: roomId, body: text)
            }
            return
        }

        // Default tap -> route to in-app playback.
        if let messageId {
            await WatchSessionStore.shared.setPendingMessage(messageId)
        }
    }
}
