import XCTest

final class RoomManagerUXContractTests: XCTestCase {
    func testEmptyRoomStateOffersCreateAndFindActions() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")

        XCTAssertTrue(source.contains("onCreateRoom"))
        XCTAssertTrue(source.contains("onFindRoom"))
        XCTAssertTrue(source.contains("룸 만들기"))
        XCTAssertTrue(source.contains("룸 찾기"))
    }

    func testEmptyRoomStateDoesNotUseNestedGlassPanel() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let emptyState = try sourceSlice(
            in: source,
            from: "private var emptyState",
            to: "private func roomCard"
        )

        XCTAssertFalse(emptyState.contains("GlassPanel"))
        XCTAssertFalse(emptyState.contains(".glassEffect()"))
    }

    func testRoomManagerCanCreateRoomFromRoomsTab() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(source.contains("createRoom()"))
        XCTAssertTrue(source.contains("roomService.createRoom"))
        XCTAssertTrue(source.contains("onCreateRoom: createRoom"))
        XCTAssertTrue(source.contains("onFindRoom: { selectedTab = .search }"))
    }

    func testRoomCreateAndRenameUpdateLocalRoomsWithoutWaitingForPolling() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(source.contains("insertOrReplaceRoom"))
        XCTAssertTrue(source.contains("renameLocalRoom"))
        XCTAssertTrue(source.contains("let createdRoom = try await roomService.createRoom"))
        XCTAssertTrue(source.contains("renameLocalRoom(roomId: roomId, newName: newName)"))
    }

    func testUserInviteUsesAtomicReuseRpcInsteadOfCreatingDuplicateRooms() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let invitationServiceSource = try readSourceFile("Ping/Backend/InvitationService.swift")
        let migration = try readSourceFile("20260518113000_invite_user_reuses_pending_room.sql")
        let handleInvite = try sourceSlice(
            in: appDelegateSource,
            from: "private func handleInvite(user: PingUser)",
            to: "private func copyInviteLink"
        )

        XCTAssertTrue(handleInvite.contains("invitationService.inviteUser"))
        XCTAssertTrue(handleInvite.contains("insertOrReplaceRoom(room)"))
        XCTAssertFalse(handleInvite.contains("roomService.createRoom"))
        XCTAssertTrue(invitationServiceSource.contains("func inviteUser"))
        XCTAssertTrue(invitationServiceSource.contains("ping_invite_user"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_invite_user"))
        XCTAssertTrue(migration.contains("existing_invitation_id"))
        XCTAssertTrue(migration.contains("existing_room_id"))
        XCTAssertTrue(migration.contains("grant execute on function public.ping_invite_user"))
    }

    func testUserSearchShowsExistingMembersAsMyRoomInsteadOfInvite() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomSearchView.swift")

        XCTAssertTrue(source.contains("sharesRoom(with: user)"))
        XCTAssertTrue(source.contains("sharesExistingRoom ? \"내 룸\" : \"초대\""))
        XCTAssertTrue(source.contains(".disabled(sharesExistingRoom || user.id == nil)"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)

        return String(source[start..<end])
    }
}
