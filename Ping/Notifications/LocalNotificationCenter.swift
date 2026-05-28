import AppKit
import UserNotifications

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

    func notifyIncomingMessage(senderNickname: String, messageId: String, roomId: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(senderNickname)님이 영상을 보냈습니다"
        content.sound = notificationSound()
        content.categoryIdentifier = Category.incomingMessage.rawValue
        content.userInfo = ["messageId": messageId, "room_id": roomId]

        let request = UNNotificationRequest(
            identifier: "ping.message.\(messageId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func notifyIncomingChat(_ message: ChatMessage, roomName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(message.senderNickname) · \(roomName)"
        let body = message.previewText.isEmpty ? "사진을 보냈습니다" : message.previewText
        content.body = body.count > 200 ? String(body.prefix(200)) + "…" : body
        content.sound = .default
        content.userInfo = [
            "type": "chat",
            "chat_id": message.id ?? "",
            "room_id": message.roomId
        ]
        let request = UNNotificationRequest(
            identifier: "chat-\(message.id ?? UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("notifyIncomingChat failed: \(error)") }
        }
    }

    /// 전환 시 한 룸의 밀린 채팅을 묶어 1건으로 알린다. 탭하면 기존 채팅 핸들러가 룸을 연다.
    func notifyChatCatchUp(roomId: String, roomName: String, unreadCount: Int, latestPreview: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(roomName) · 새 메시지 \(unreadCount)개"
        let body = latestPreview.isEmpty ? "사진을 보냈습니다" : latestPreview
        content.body = body.count > 200 ? String(body.prefix(200)) + "…" : body
        content.sound = notificationSound()
        content.userInfo = [
            "type": "chat",
            "chat_id": "",
            "room_id": roomId
        ]
        let request = UNNotificationRequest(
            identifier: "chat-catchup-\(roomId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("notifyChatCatchUp failed: \(error)") }
        }
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
                guard info["room_id"] as? String == roomId else { return nil }
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
        let messageId = info["messageId"] as? String
        let messageRoomId = info["room_id"] as? String
        let inviteId = info["inviteId"] as? String
        let infoType = info["type"] as? String
        let chatId = info["chat_id"] as? String
        let chatRoomId = info["room_id"] as? String

        Task { @MainActor in
            if infoType == "update",
               actionIdentifier == Action.viewUpdate.rawValue || actionIdentifier == UNNotificationDefaultActionIdentifier {
                onCheckForUpdates?()
                return
            }

            // Chat notifications are identified by their "type" key.
            if infoType == "chat",
               let chatId, let chatRoomId {
                clearDeliveredNotifications(roomId: chatRoomId)
                onViewChatMessage?(chatId, chatRoomId)
                return
            }

            switch actionIdentifier {
            case Action.viewMessage.rawValue, UNNotificationDefaultActionIdentifier:
                if let messageId {
                    if let messageRoomId {
                        clearDeliveredNotifications(roomId: messageRoomId)
                    }
                    onViewMessage?(messageId)
                } else if let inviteId {
                    _ = inviteId
                    onOpenInvitations?()
                }
            case Action.acceptInvite.rawValue:
                if let inviteId {
                    onAcceptInvitation?(inviteId)
                }
            case Action.rejectInvite.rawValue:
                if let inviteId {
                    onRejectInvitation?(inviteId)
                }
            default:
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

    private func notificationSound() -> UNNotificationSound? {
        switch PingNotificationSound.current {
        case .systemDefault:
            return .default
        case .none:
            return nil
        }
    }
}
