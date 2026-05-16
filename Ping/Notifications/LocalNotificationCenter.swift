import AppKit
import UserNotifications

@MainActor
final class LocalNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationCenter()

    enum Category: String {
        case incomingMessage = "ping.message"
        case incomingInvitation = "ping.invitation"
    }

    enum Action: String {
        case viewMessage = "ping.view"
        case acceptInvite = "ping.accept"
        case rejectInvite = "ping.reject"
    }

    var onViewMessage: ((String) -> Void)?
    var onOpenInvitations: (() -> Void)?
    var onAcceptInvitation: ((String) -> Void)?
    var onRejectInvitation: ((String) -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            registerCategories()
            return granted
        } catch {
            return false
        }
    }

    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: Action.viewMessage.rawValue,
            title: "보기",
            options: [.foreground]
        )
        let messageCategory = UNNotificationCategory(
            identifier: Category.incomingMessage.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let accept = UNNotificationAction(
            identifier: Action.acceptInvite.rawValue,
            title: "수락",
            options: [.foreground]
        )
        let reject = UNNotificationAction(
            identifier: Action.rejectInvite.rawValue,
            title: "거부",
            options: [.destructive]
        )
        let invitationCategory = UNNotificationCategory(
            identifier: Category.incomingInvitation.rawValue,
            actions: [accept, reject],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([messageCategory, invitationCategory])
    }

    func notifyIncomingMessage(senderNickname: String, messageId: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(senderNickname)님이 영상을 보냈습니다"
        content.sound = notificationSound()
        content.categoryIdentifier = Category.incomingMessage.rawValue
        content.userInfo = ["messageId": messageId]

        let request = UNNotificationRequest(
            identifier: "ping.message.\(messageId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func notifyIncomingInvitation(_ invitation: Invitation) {
        let inviteId = invitation.id ?? UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "\(invitation.fromNickname)님이 룸에 초대했습니다"
        content.body = invitation.roomName
        content.sound = notificationSound()
        content.categoryIdentifier = Category.incomingInvitation.rawValue
        content.userInfo = ["inviteId": inviteId]

        let request = UNNotificationRequest(
            identifier: "ping.invitation.\(inviteId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        Task { @MainActor in
            switch actionIdentifier {
            case Action.viewMessage.rawValue, UNNotificationDefaultActionIdentifier:
                if let messageId = info["messageId"] as? String {
                    onViewMessage?(messageId)
                } else if let inviteId = info["inviteId"] as? String {
                    _ = inviteId
                    onOpenInvitations?()
                }
            case Action.acceptInvite.rawValue:
                if let inviteId = info["inviteId"] as? String {
                    onAcceptInvitation?(inviteId)
                }
            case Action.rejectInvite.rawValue:
                if let inviteId = info["inviteId"] as? String {
                    onRejectInvitation?(inviteId)
                }
            default:
                break
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func notificationSound() -> UNNotificationSound? {
        switch PingNotificationSound.current {
        case .systemDefault:
            return .default
        case .none:
            return nil
        }
    }
}
