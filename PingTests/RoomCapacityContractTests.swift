import XCTest

final class RoomCapacityContractTests: XCTestCase {
    func testRoomLimitsAreEightRoomsAndFourMembers() throws {
        let limitsSource = try readSourceFile("Ping/Core/RoomLimits.swift")
        let migration = try readSourceFile("supabase/migrations/20260518003000_room_capacity_limits.sql")

        XCTAssertTrue(limitsSource.contains("maxRoomsPerUser = 8"))
        XCTAssertTrue(limitsSource.contains("maxMembersPerRoom = 4"))
        XCTAssertTrue(migration.contains("current_room_count >= 8"))
        XCTAssertTrue(migration.contains("current_count >= 4"))
        XCTAssertTrue(migration.contains("member_count >= 4"))
        XCTAssertTrue(migration.contains("case when current_count >= 4 then 'full' else 'open' end"))
    }

    func testRoomNameLimitIsSixteenCharactersAcrossAppAndDatabase() throws {
        let limitsSource = try readSourceFile("Ping/Core/RoomLimits.swift")
        let roomServiceSource = try readSourceFile("Ping/Backend/RoomService.swift")
        let invitationServiceSource = try readSourceFile("Ping/Backend/InvitationService.swift")
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let migration = try readSourceFile("20260523000600_room_name_length_limit.sql")

        XCTAssertTrue(limitsSource.contains("maxRoomNameLength = 16"))
        XCTAssertTrue(limitsSource.contains("sanitizedRoomName"))
        XCTAssertTrue(limitsSource.contains("directRoomName(myNickname: String, otherNickname: String)"))
        XCTAssertTrue(roomServiceSource.contains("RoomLimits.sanitizedRoomName(name)"))
        XCTAssertTrue(roomServiceSource.contains("RoomLimits.sanitizedRoomName(newName)"))
        XCTAssertTrue(invitationServiceSource.contains("RoomLimits.sanitizedRoomName(roomName)"))
        XCTAssertTrue(appDelegateSource.contains("RoomLimits.directRoomName"))
        XCTAssertTrue(migration.contains("rooms_name_length_limit"))
        XCTAssertTrue(migration.contains("char_length(btrim(name)) between 1 and 16"))
        XCTAssertTrue(migration.contains("not valid"))
    }

    func testAppAndMessageSendingUseGroupRoomMembershipRules() throws {
        let appStateSource = try readSourceFile("Ping/Core/AppState.swift")
        let messageSource = try readSourceFile("Ping/Backend/MessageService.swift")
        let mirrorSource = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")

        XCTAssertFalse(appStateSource.contains("memberUids.count == 2"))
        XCTAssertFalse(messageSource.contains("memberUids.count == 2"))
        XCTAssertFalse(mirrorSource.contains("memberUids.count == 2"))
        XCTAssertTrue(appStateSource.contains("RoomLimits.minSendableMembers"))
        XCTAssertTrue(messageSource.contains("RoomLimits.minSendableMembers"))
        XCTAssertTrue(messageSource.contains("for receiverUid in receiverUids"))
        XCTAssertTrue(mirrorSource.contains("RoomLimits.minSendableMembers"))
    }

    func testRoomManagerLetsUsersCreateMoreRoomsUntilLimit() throws {
        let roomListSource = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let roomManagerSource = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(roomListSource.contains("RoomLimits.maxRoomsPerUser"))
        XCTAssertTrue(roomListSource.contains("roomCountHeader"))
        XCTAssertTrue(roomListSource.contains("canCreateRoom"))
        XCTAssertTrue(roomManagerSource.contains("appState.rooms.count < RoomLimits.maxRoomsPerUser"))
        XCTAssertFalse(roomManagerSource.contains("새 1:1 룸 이름"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
