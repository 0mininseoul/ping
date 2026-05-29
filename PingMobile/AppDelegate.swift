import UIKit
import UserNotifications
import PingKit

/// iOS app delegate: registers for APNs, declares the reply notification
/// category, and handles the inline dictation reply by posting to room chat.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let replyCategoryId = "PING_MESSAGE"
    static let replyActionId = "PING_REPLY"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Inline dictation/scribble reply, shown on iPhone and forwarded to Apple Watch.
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyActionId,
            title: "답장",
            options: [],
            textInputButtonTitle: "보내기",
            textInputPlaceholder: "메시지 입력"
        )
        let category = UNNotificationCategory(
            identifier: Self.replyCategoryId,
            actions: [reply],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushRegistrar.shared.update(token: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Registration failures surface again on next launch; nothing to persist.
    }

    // Show the banner even while the app is foregrounded (useful during testing).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Inline reply -> ping_send_chat to the originating room.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let textResponse = response as? UNTextInputNotificationResponse else { return }
        let userInfo = response.notification.request.content.userInfo
        guard let roomId = userInfo["roomId"] as? String else { return }
        let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let client = await AppEnvironment.shared.makeClient() {
            try? await client.sendChat(roomId: roomId, body: text)
        }
    }
}
