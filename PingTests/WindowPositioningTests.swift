import XCTest
@testable import Ping

final class WindowPositioningTests: XCTestCase {
    func testVisibleOriginClampsSavedMirrorPositionFromCurrentMac() {
        let visibleFrame = CGRect(x: 0, y: 47, width: 1800, height: 1083)
        let origin = WindowPositioning.visibleOrigin(
            preferred: CGPoint(x: 2521, y: 361),
            windowSize: CGSize(width: 200, height: 200),
            in: visibleFrame
        )

        XCTAssertEqual(origin.x, 1600, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 361, accuracy: 0.0001)
    }

    func testVisibleOriginCentersWindowWhenNoSavedPositionExists() {
        let visibleFrame = CGRect(x: 0, y: 47, width: 1800, height: 1083)
        let origin = WindowPositioning.visibleOrigin(
            preferred: nil,
            windowSize: CGSize(width: 200, height: 200),
            in: visibleFrame
        )

        XCTAssertEqual(origin.x, 800, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 488.5, accuracy: 0.0001)
    }

    func testVisibleOriginHandlesEmptyScreenFrame() {
        let origin = WindowPositioning.visibleOrigin(
            preferred: CGPoint(x: 2521, y: 361),
            windowSize: CGSize(width: 200, height: 200),
            in: .zero
        )

        XCTAssertEqual(origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.0001)
    }
}
