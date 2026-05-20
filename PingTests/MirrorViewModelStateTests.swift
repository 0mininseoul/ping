import XCTest
@testable import Ping

@MainActor
final class MirrorViewModelStateTests: XCTestCase {
    func test_initialState_isIdle() {
        let vm = MirrorViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.countdown, 3)
    }

    func test_enterReviewing_setsReviewingStateWithURL() {
        let vm = MirrorViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        vm.enterReviewing(url: url)
        XCTAssertEqual(vm.state, .reviewing(url))
    }

    func test_beginUpload_transitionsFromReviewingToUploading() {
        let vm = MirrorViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        vm.enterReviewing(url: url)
        vm.beginUpload()
        XCTAssertEqual(vm.state, .uploading)
    }

    func test_redo_resetsToRecordingWithCountdown() {
        let vm = MirrorViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        vm.enterReviewing(url: url)
        vm.countdown = 1
        vm.redo()
        XCTAssertEqual(vm.state, .recording)
        XCTAssertEqual(vm.countdown, 3)
    }

    func test_reset_returnsToIdle() {
        let vm = MirrorViewModel()
        vm.state = .failed("err")
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.countdown, 3)
    }
}
