import XCTest
@testable import Ping

@MainActor
final class PartnerCyclingTests: XCTestCase {
    private func room(id: String) -> Room {
        Room(
            id: id,
            name: id,
            searchableName: id,
            ownerUid: "u1",
            memberUids: ["u1", "u2"],
            memberNicknames: ["u1": "me", "u2": "partner"],
            status: .full
        )
    }

    func testCycleSingleRoomAlwaysReturnsSame() {
        let state = AppState()
        state.rooms = [room(id: "a")]

        XCTAssertEqual(state.cycleToNextPartner(currentRoomId: "a")?.id, "a")
        XCTAssertEqual(state.cycleToNextPartner(currentRoomId: nil)?.id, "a")
    }

    func testCycleThreeRoomsMovesForwardThenWraps() {
        let state = AppState()
        state.rooms = [room(id: "a"), room(id: "b"), room(id: "c")]

        XCTAssertEqual(state.cycleToNextPartner(currentRoomId: "a")?.id, "b")
        XCTAssertEqual(state.cycleToNextPartner(currentRoomId: "b")?.id, "c")
        XCTAssertEqual(state.cycleToNextPartner(currentRoomId: "c")?.id, "a")
    }

    func testSelectAtValidIndex() {
        let state = AppState()
        state.rooms = [room(id: "a"), room(id: "b"), room(id: "c")]

        XCTAssertEqual(state.selectPartner(at: 1)?.id, "a")
        XCTAssertEqual(state.selectPartner(at: 3)?.id, "c")
        XCTAssertNil(state.selectPartner(at: 0))
        XCTAssertNil(state.selectPartner(at: 4))
    }
}
