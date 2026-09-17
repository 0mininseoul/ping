import XCTest
@testable import Ping

final class RoomFocusPolicyTests: XCTestCase {
    private let room = "room-1"

    // MARK: - Room focus policy

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

    // MARK: - Initial room selection

    /// 회귀 방지: 채팅 알림을 클릭하면 AppDelegate가 pendingRoomFocusId를 먼저 세우고
    /// 룸 창을 연다. 창이 닫혀 있었으면 뷰가 그 뒤에 새로 만들어져 onChange가 변경을
    /// 놓쳤고, onAppear 경로는 pending을 보지 않아 직전에 보던 룸이 열렸다.
    func testNotificationFocusWinsOverTheLastSelectedRoom() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: "room-2",
            currentSelectionId: nil,
            lastSelectedRoomId: "room-1",
            availableRoomIds: ["room-1", "room-2"],
            defaultRoomId: "room-1"
        )

        XCTAssertEqual(selection.roomId, "room-2")
        XCTAssertTrue(selection.consumesPendingFocus)
    }

    func testNotificationFocusWinsOverAnExistingSelection() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: "room-2",
            currentSelectionId: "room-1",
            lastSelectedRoomId: "room-1",
            availableRoomIds: ["room-1", "room-2"],
            defaultRoomId: "room-1"
        )

        XCTAssertEqual(selection.roomId, "room-2")
        XCTAssertTrue(selection.consumesPendingFocus)
    }

    /// 알림이 가리키는 룸이 아직 로드되지 않았으면 pending을 소비하면 안 된다.
    /// 소비해버리면 룸 목록이 도착한 뒤 적용할 기회가 사라진다.
    func testAnUnloadedNotificationRoomKeepsThePendingFocus() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: "room-2",
            currentSelectionId: nil,
            lastSelectedRoomId: "room-1",
            availableRoomIds: ["room-1"],
            defaultRoomId: "room-1"
        )

        XCTAssertEqual(selection.roomId, "room-1")
        XCTAssertFalse(selection.consumesPendingFocus)
    }

    func testAValidSelectionIsKeptWithoutPendingFocus() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: nil,
            currentSelectionId: "room-2",
            lastSelectedRoomId: "room-1",
            availableRoomIds: ["room-1", "room-2"],
            defaultRoomId: "room-1"
        )

        XCTAssertEqual(selection.roomId, "room-2")
        XCTAssertFalse(selection.consumesPendingFocus)
    }

    func testAStaleSelectionFallsBackToTheLastSelectedRoom() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: nil,
            currentSelectionId: "left-room",
            lastSelectedRoomId: "room-1",
            availableRoomIds: ["room-1", "room-2"],
            defaultRoomId: "room-2"
        )

        XCTAssertEqual(selection.roomId, "room-1")
    }

    func testWithoutAnyHistoryTheDefaultRoomWins() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: nil,
            currentSelectionId: nil,
            lastSelectedRoomId: nil,
            availableRoomIds: ["room-1", "room-2"],
            defaultRoomId: "room-2"
        )

        XCTAssertEqual(selection.roomId, "room-2")
    }

    func testWithoutADefaultRoomTheFirstRoomWins() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: nil,
            currentSelectionId: nil,
            lastSelectedRoomId: nil,
            availableRoomIds: ["room-1", "room-2"],
            defaultRoomId: nil
        )

        XCTAssertEqual(selection.roomId, "room-1")
    }

    func testNoRoomsSelectsNothing() {
        let selection = RoomFocusPolicy.initialRoomSelection(
            pendingRoomFocusId: "room-2",
            currentSelectionId: nil,
            lastSelectedRoomId: "room-1",
            availableRoomIds: [],
            defaultRoomId: nil
        )

        XCTAssertNil(selection.roomId)
        XCTAssertFalse(selection.consumesPendingFocus)
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

    func testAppDelegateChecksAppActivationForPresence() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")

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

    /// 회귀 방지: 룸 창을 열어둔 채 다른 앱을 쓰는 동안 새 채팅이 오면, 방금 올라간
    /// 알림이 룸 선택 변경 경로로 1~2초 뒤 지워져 사용자는 아무것도 못 봤다.
    func testBackgroundRoomSelectionDoesNotClearFreshNotifications() throws {
        let source = try readRepositoryFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(source.contains("if let newValue, NSApp.isActive {"))
        XCTAssertFalse(
            source.contains("if let newValue {\n                LocalNotificationCenter.shared.clearDeliveredNotifications")
        )
    }

    /// 회귀 방지: 룸 창이 닫혀 있을 때 알림을 클릭하면 뷰가 새로 만들어지면서
    /// onChange가 pendingRoomFocusId 변경을 놓친다. onAppear 경로도 같은 정책을
    /// 타야 알림이 가리키는 룸이 열린다.
    func testTheRoomWindowAlwaysHonorsTheNotificationFocus() throws {
        let source = try readRepositoryFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(source.contains("RoomFocusPolicy.initialRoomSelection("))
        XCTAssertTrue(source.contains("pendingRoomFocusId: appState.pendingRoomFocusId"))
        // pending을 보지 않던 옛 선택 로직이 남아 있으면 안 된다.
        XCTAssertFalse(source.contains("let persistedId = appState.lastSelectedRoomId"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
