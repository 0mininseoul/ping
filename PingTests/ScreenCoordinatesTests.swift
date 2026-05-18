import XCTest
@testable import Ping

final class ScreenCoordinatesTests: XCTestCase {
    func testNormalizeCenterOfScreenReturnsHalfHalf() {
        let pos = ScreenCoordinates.normalize(
            point: CGPoint(x: 960, y: 540),
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(pos.xRatio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pos.yRatio, 0.5, accuracy: 0.0001)
    }

    func testNormalizeClampsPointsOutsideScreenToValidRatios() {
        let pos = ScreenCoordinates.normalize(
            point: CGPoint(x: 2200, y: -100),
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(pos.xRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(pos.yRatio, 0.0, accuracy: 0.0001)
    }

    func testDenormalizeHalfHalfReturnsCenter() {
        let point = ScreenCoordinates.denormalize(
            position: MirrorPosition(xRatio: 0.5, yRatio: 0.5),
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(point.x, 960, accuracy: 0.0001)
        XCTAssertEqual(point.y, 540, accuracy: 0.0001)
    }

    func testClampPointBeyondRightEdgeClampsToSafeArea() {
        let safe = CGRect(x: 0, y: 24, width: 1920, height: 1056)
        let clamped = ScreenCoordinates.clamp(
            point: CGPoint(x: 2000, y: 540),
            windowSize: CGSize(width: 200, height: 200),
            inSafeArea: safe
        )

        XCTAssertEqual(clamped.x, 1720, accuracy: 0.0001)
    }

    func testClampPointBeyondTopEdgeClampsBelowMenuBar() {
        let safe = CGRect(x: 0, y: 24, width: 1920, height: 1056)
        let clamped = ScreenCoordinates.clamp(
            point: CGPoint(x: 500, y: 0),
            windowSize: CGSize(width: 200, height: 200),
            inSafeArea: safe
        )

        XCTAssertEqual(clamped.y, 24, accuracy: 0.0001)
    }
}
