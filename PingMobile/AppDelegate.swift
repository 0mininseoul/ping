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
        WatchBridge.shared.activate()
        if let account = AppEnvironment.shared.paired {
            WatchBridge.shared.sync(account)
        }

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

    // NOTE: These use the completion-handler (non-async) delegate signatures on
    // purpose. The async-bridged variants resume their auto-generated completion
    // closure on a background cooperative executor; UIKit then performs
    // main-thread-only snapshot/state-restoration work synchronously off the back
    // of that completion and aborts with an NSInternalInconsistency assertion
    // (build 4 crashed the moment a notification was tapped). Invoking the
    // completion handler on the main thread keeps that follow-up work on-main.

    // Show the banner even while the app is foregrounded (useful during testing).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // `Unchecked` lets us hop the non-Sendable completion handler to the main
        // queue under Swift 6 region isolation; we only ever invoke it on main.
        let handler = Unchecked(completionHandler)
        DispatchQueue.main.async { handler.value([.banner, .sound]) }
    }

    // Tap (default action) -> deep-link into the room thread.
    // Reply action -> post the dictated text to the room.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let handler = Unchecked(completionHandler)
        let roomId = response.notification.request.content.userInfo["roomId"] as? String

        // Inline dictation reply.
        if response.actionIdentifier == Self.replyActionId,
           let textResponse = response as? UNTextInputNotificationResponse,
           let roomId {
            let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                DispatchQueue.main.async { handler.value() }
                return
            }
            // Keep the app alive until posted; resume on the main actor so the
            // completion (and UIKit's follow-up work) runs on the main thread.
            Task { @MainActor in
                if let client = AppEnvironment.shared.makeClient() {
                    try? await client.sendChat(roomId: roomId, body: text)
                }
                handler.value()
            }
            return
        }

        // Default tap (or dismiss): open the room's thread if we know the room.
        Task { @MainActor in
            if let roomId {
                AppEnvironment.shared.pendingRoute = .thread(roomId: roomId)
            }
            handler.value()
        }
    }
}

/// Transports a non-Sendable value across an isolation boundary. Safe only when
/// the value is used on a single, known executor (here: the main queue).
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
