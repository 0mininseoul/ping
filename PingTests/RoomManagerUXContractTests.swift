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
