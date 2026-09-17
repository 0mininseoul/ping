import AppKit
import UserNotifications

/// APNs and the legacy local notification path use different naming conventions
/// for identifiers. Parse both into one value before routing an action so a
/// cold-start APNs payload follows the same handlers as an existing delivery.
enum NotificationPayload: Equatable {
    case message(messageId: String, roomId: String?)
    case invitation(inviteId: String, roomId: String?)
    case chat(chatId: String?, roomId: String)
    case update(version: String?)
    case unknown

    var roomId: String? {
        switch self {
        case .message(_, let roomId), .invitation(_, let roomId):
            return roomId
        case .chat(_, let roomId):
            return roomId
        case .update, .unknown:
            return nil
        }
    }

    static func parse(userInfo: [AnyHashable: Any]) -> NotificationPayload {
        let type = string(in: userInfo, keys: ["type", "notification_type", "event_type"])
        let messageId = string(in: userInfo, keys: ["messageId", "message_id", "message_uuid"])
        let inviteId = string(in: userInfo, keys: ["inviteId", "invite_id", "invitationId", "invitation_id"])
        let chatId = string(in: userInfo, keys: ["chat_id", "chatId", "chat_uuid"])
        let roomId = string(in: userInfo, keys: ["room_id", "roomId", "room_uuid"])
        let version = string(in: userInfo, keys: ["version", "app_version"])

        if type == "update" {
            return .update(version: version)
        }

        if type == "chat", let roomId {
            return .chat(chatId: chatId, roomId: roomId)
        }

        if let messageId {
            return .message(messageId: messageId, roomId: roomId)
        }

        if let inviteId {
            return .invitation(inviteId: inviteId, roomId: roomId)
        }

        if let chatId, let roomId {
            return .chat(chatId: chatId, roomId: roomId)
        }

        if version != nil {
            return .update(version: version)
        }

        return .unknown
    }

    private static func string(in userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = userInfo[AnyHashable(key)] as? String else { continue }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty { return normalized }
        }
        return nil
    }
}

@MainActor
final class LocalNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationCenter()
    static let updateAvailableIdentifier = "ping.update.available"

    enum Category: String {
        case incomingMessage = "ping.message"
        case incomingInvitation = "ping.invitation"
        case availableUpdate = "ping.update"
    }

    enum Action: String {
        case viewMessage = "ping.view"
        case acceptInvite = "ping.accept"
        case rejectInvite = "ping.reject"
        case viewUpdate = "ping.update.view"
    }

    var onViewMessage: ((String) -> Void)?
    var onOpenInvitations: (() -> Void)?
    var onAcceptInvitation: ((String) -> Void)?
    var onRejectInvitation: ((String) -> Void)?
    var onViewChatMessage: ((_ chatId: String, _ roomId: String) -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func configure() {
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            registerCategories()
            if granted {
                RemotePushRegistrar.shared.registerForRemoteNotifications()
            }
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

        let viewUpdate = UNNotificationAction(
            identifier: Action.viewUpdate.rawValue,
            title: "업데이트 보기",
            options: [.foreground]
        )
        let updateCategory = UNNotificationCategory(
            identifier: Category.availableUpdate.rawValue,
            actions: [viewUpdate],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            messageCategory,
            invitationCategory,
            updateCategory
        ])
    }

    func notifyUpdateAvailable(version: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.updateAvailableIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.updateAvailableIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Ping \(version) 업데이트 가능"
        content.body = "클릭하면 변경 내용을 확인하고 바로 설치할 수 있습니다."
        content.sound = .default
        content.categoryIdentifier = Category.availableUpdate.rawValue
        content.userInfo = ["type": "update", "version": version]

        let request = UNNotificationRequest(
            identifier: Self.updateAvailableIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func clearUpdateAvailableNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.updateAvailableIdentifier]
        )
    }

    func clearDeliveredNotifications(roomId: String) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                let info = notification.request.content.userInfo
                let parsedRoomId = NotificationPayload.parse(userInfo: info).roomId
                guard parsedRoomId == roomId || info["room_id"] as? String == roomId else { return nil }
                return notification.request.identifier
            }
            guard !identifiers.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let payload = NotificationPayload.parse(userInfo: info)

        Task { @MainActor in
            if case .update = payload,
               actionIdentifier == Action.viewUpdate.rawValue || actionIdentifier == UNNotificationDefaultActionIdentifier {
                onCheckForUpdates?()
                return
            }

            switch payload {
            case .chat(let chatId, let roomId):
                // 쓸어 넘겨 지운 것(dismiss)은 "보겠다"가 아니다. 구분하지 않으면 알림을
                // 지우기만 해도 룸이 열리고 그 룸의 알림이 전부 정리된다.
                guard actionIdentifier != UNNotificationDismissActionIdentifier else { return }
                clearDeliveredNotifications(roomId: roomId)
                onViewChatMessage?(chatId ?? "", roomId)
            case .message(let messageId, let roomId):
                guard actionIdentifier == Action.viewMessage.rawValue
                    || actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
                if let roomId {
                    clearDeliveredNotifications(roomId: roomId)
                }
                onViewMessage?(messageId)
            case .invitation(let inviteId, _):
                // Invitation notifications can be opened from the default
                // action, while accept/reject preserve their dedicated actions.
                switch actionIdentifier {
                case Action.viewMessage.rawValue, UNNotificationDefaultActionIdentifier:
                    onOpenInvitations?()
                case Action.acceptInvite.rawValue:
                    onAcceptInvitation?(inviteId)
                case Action.rejectInvite.rawValue:
                    onRejectInvitation?(inviteId)
                default:
                    break
                }
            case .update, .unknown:
                break
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

}
