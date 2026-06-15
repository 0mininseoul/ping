import XCTest

final class RoomPollingContractTests: XCTestCase {
    func testRoomPollingDoesNotReplaceTransientFailuresWithEmptySnapshots() throws {
        let source = try readSourceFile("RoomService.swift")

        XCTAssertTrue(source.contains("Room polling failed"))
        XCTAssertFalse(source.contains("continuation.yield([])"))
    }

    private func readSourceFile(_ fileName: String) throws -> String {
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
