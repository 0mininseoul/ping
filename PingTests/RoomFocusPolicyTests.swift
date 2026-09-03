import XCTest
@testable import Ping

final class RoomFocusPolicyTests: XCTestCase {
    private let room = "room-1"

    // MARK: - Chat notification suppression

    func testViewingTheRoomSuppressesItsChatNotification() {
        XCTAssertTrue(
            RoomFocusPolicy.isViewingRoom(
                roomId: room,
                appIsActive: true,
                roomWindowIsVisible: true,
                pendingRoomFocusId: nil,
                lastSelectedRoomId: room
            )
        )
    }

    /// 회귀 방지: NSWindow.isVisible은 창이 다른 앱에 완전히 가려져 있어도 true다.
    /// 룸 창을 열어둔 채 다른 일을 하는 동안 도착한 채팅 알림이 조용히 사라졌다.
    func testAnOccludedRoomWindowStillNotifies() {
        XCTAssertFalse(
            RoomFocusPolicy.isViewingRoom(
                roomId: room,
                appIsActive: false,
                roomWindowIsVisible: true,
                pendingRoomFocusId: nil,
                lastSelectedRoomId: room
            )
        )
    }

    func testClosedRoomWindowNotifies() {
        XCTAssertFalse(
            RoomFocusPolicy.isViewingRoom(
                roomId: room,
                appIsActive: true,
                roomWindowIsVisible: false,
                pendingRoomFocusId: nil,
                lastSelectedRoomId: room
            )
        )
    }

    func testADifferentRoomStillNotifies() {
        XCTAssertFalse(
            RoomFocusPolicy.isViewingRoom(
                roomId: room,
                appIsActive: true,
                roomWindowIsVisible: true,
                pendingRoomFocusId: nil,
                lastSelectedRoomId: "other-room"
            )
        )
    }

    func testPendingFocusCountsAsViewing() {
        XCTAssertTrue(
            RoomFocusPolicy.isViewingRoom(
                roomId: room,
                appIsActive: true,
                roomWindowIsVisible: true,
                pendingRoomFocusId: room,
                lastSelectedRoomId: "other-room"
            )
        )
    }

    // MARK: - Mobile push presence

    func testPresenceReportsTheRoomOnlyWhileActuallyViewing() {
        XCTAssertEqual(
            RoomFocusPolicy.activeRoomIdForPresence(
                appIsActive: true,
                roomWindowIsVisible: true,
                lastSelectedRoomId: room
            ),
            room
        )
    }

    /// 가려진 창을 "보고 있다"로 보고하면 데스크톱과 휴대폰 양쪽에서 알림이 사라진다.
    func testPresenceIsNilWhenTheAppIsNotActive() {
        XCTAssertNil(
            RoomFocusPolicy.activeRoomIdForPresence(
                appIsActive: false,
                roomWindowIsVisible: true,
                lastSelectedRoomId: room
            )
        )
    }

    func testPresenceIsNilWhenTheWindowIsClosed() {
        XCTAssertNil(
            RoomFocusPolicy.activeRoomIdForPresence(
                appIsActive: true,
                roomWindowIsVisible: false,
                lastSelectedRoomId: room
            )
        )
    }

    // MARK: - Source contract

    func testAppDelegateChecksAppActivationForBothPaths() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("RoomFocusPolicy.isViewingRoom("))
        XCTAssertTrue(source.contains("RoomFocusPolicy.activeRoomIdForPresence("))
        XCTAssertTrue(source.contains("appIsActive: NSApp.isActive"))
        // 창 가시성만 보던 옛 판단이 남아 있으면 안 된다.
        XCTAssertFalse(source.contains("guard let roomManagerWindow, roomManagerWindow.isVisible else { return nil }"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

// MARK: - Chat notification handling contracts

final class ChatNotificationHandlingContractTests: XCTestCase {
    /// 회귀 방지: dismiss도 "보겠다"로 처리해 알림을 쓸어 지우면 룸이 열리고
    /// 그 룸의 알림이 전부 정리됐다. 계측 결과를 오독하게 만든 원인이기도 하다.
    func testDismissingAChatNotificationDoesNotOpenTheRoom() throws {
        let source = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")

        XCTAssertTrue(
            source.contains("guard actionIdentifier != UNNotificationDismissActionIdentifier else { return }")
        )
    }

    /// 설정의 "알림 소리"는 수신 알림 전체에 적용된다고 안내한다.
    func testChatNotificationsRespectTheSoundPreference() throws {
        let source = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")

        let chatBody = try sourceSlice(
            in: source,
            from: "func notifyIncomingChat(",
            to: "func notifyChatCatchUp("
        )
        XCTAssertTrue(chatBody.contains("content.sound = notificationSound()"))
        XCTAssertFalse(chatBody.contains("content.sound = .default"))
    }

    /// 회귀 방지: 룸 창을 열어둔 채 다른 앱을 쓰는 동안 새 채팅이 오면, 방금 올라간
    /// 알림이 룸 선택 변경 경로로 1~2초 뒤 지워져 사용자는 아무것도 못 봤다.
    /// 계측(chat_notify_decision)은 suppressed=false였는데 알림이 사라진 이유가 이것이다.
    func testBackgroundRoomSelectionDoesNotClearFreshNotifications() throws {
        let source = try readRepositoryFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(source.contains("if let newValue, NSApp.isActive {"))
        XCTAssertFalse(
            source.contains("if let newValue {\n                LocalNotificationCenter.shared.clearDeliveredNotifications")
        )
    }

    /// 이 결정은 원격에서 관측할 수 없어 여러 차례 오진했다.
    func testTheNotifyDecisionIsInstrumented() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("\"chat_notify_decision\""))
        XCTAssertTrue(source.contains("\"suppressed\": isViewingRoom"))
        XCTAssertTrue(source.contains("\"app_active\": NSApp.isActive"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
