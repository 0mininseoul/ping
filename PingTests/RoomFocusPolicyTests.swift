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
