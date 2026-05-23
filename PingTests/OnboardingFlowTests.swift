import XCTest
@testable import Ping

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testCreateRoomFlowUsesContiguousDisplayedSteps() {
        let viewModel = PairingViewModel()

        advanceToConnectionChoice(viewModel)
        XCTAssertEqual(viewModel.displayedStepNumber, 4)
        XCTAssertEqual(viewModel.displayedStepCount, 6)

        viewModel.chooseCreateRoom()
        XCTAssertEqual(viewModel.displayedStepNumber, 5)
        XCTAssertEqual(viewModel.displayedStepCount, 6)

        viewModel.roomName = "QA Room"
        viewModel.completeCreateRoom()
        XCTAssertEqual(viewModel.displayedStepNumber, 6)
        XCTAssertEqual(viewModel.displayedStepCount, 6)
    }

    func testJoinRoomFlowUsesContiguousDisplayedSteps() {
        let viewModel = PairingViewModel()

        advanceToConnectionChoice(viewModel)
        viewModel.chooseJoinRoom()
        XCTAssertEqual(viewModel.displayedStepNumber, 5)
        XCTAssertEqual(viewModel.displayedStepCount, 6)

        viewModel.selectRoomForJoin(
            Room(
                id: "room-id",
                name: "QA Room",
                searchableName: "qa room",
                ownerUid: "owner",
                memberUids: ["owner"],
                memberNicknames: ["owner": "Owner"],
                status: .open
            )
        )
        XCTAssertEqual(viewModel.displayedStepNumber, 6)
        XCTAssertEqual(viewModel.displayedStepCount, 6)
    }

    private func advanceToConnectionChoice(_ viewModel: PairingViewModel) {
        viewModel.next()
        viewModel.next()
        viewModel.nickname = "QA"
        viewModel.next()
    }
}
