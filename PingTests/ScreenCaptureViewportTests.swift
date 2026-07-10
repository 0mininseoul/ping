import CoreImage
import XCTest
@testable import Ping

final class ScreenCaptureViewportTests: XCTestCase {
    func testDefaultViewportCapturesTheFullFrame() {
        let viewport = ScreenCaptureViewport()
        let extent = CGRect(x: 10, y: 20, width: 1920, height: 1080)

        XCTAssertEqual(viewport.zoom, 1)
        XCTAssertEqual(viewport.center, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(viewport.cropRect(in: extent), extent)
    }

    func testZoomKeepsTheCropCenteredAndPreservesAspectRatio() {
        var viewport = ScreenCaptureViewport()
        viewport.adjustZoom(by: 1)

        let crop = viewport.cropRect(in: CGRect(x: 0, y: 0, width: 1920, height: 1080))

        XCTAssertEqual(viewport.zoom, 2)
        XCTAssertEqual(crop, CGRect(x: 480, y: 270, width: 960, height: 540))
        XCTAssertEqual(crop.width / crop.height, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testPointerMovementClampsTheCropInsideTheCapturedDisplay() {
        var viewport = ScreenCaptureViewport(zoom: 2)
        let display = CGRect(x: 100, y: 200, width: 1000, height: 800)

        XCTAssertTrue(viewport.moveCenter(toScreenPoint: CGPoint(x: 100, y: 200), in: display))
        XCTAssertEqual(viewport.center, CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(
            viewport.cropRect(in: CGRect(x: 0, y: 0, width: 2000, height: 1600)),
            CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        XCTAssertTrue(viewport.moveCenter(toScreenPoint: CGPoint(x: 1100, y: 1000), in: display))
        XCTAssertEqual(viewport.center, CGPoint(x: 0.75, y: 0.75))
        XCTAssertEqual(
            viewport.cropRect(in: CGRect(x: 0, y: 0, width: 2000, height: 1600)),
            CGRect(x: 1000, y: 800, width: 1000, height: 800)
        )
    }

    func testPointerOutsideCapturedDisplayDoesNotMoveViewport() {
        var viewport = ScreenCaptureViewport(zoom: 2)

        XCTAssertFalse(
            viewport.moveCenter(
                toScreenPoint: CGPoint(x: 1200, y: 400),
                in: CGRect(x: 0, y: 0, width: 1000, height: 800)
            )
        )
        XCTAssertEqual(viewport.center, CGPoint(x: 0.5, y: 0.5))
    }

    func testZoomAndResetStayWithinSupportedRange() {
        var viewport = ScreenCaptureViewport()

        viewport.adjustZoom(by: 20)
        XCTAssertEqual(viewport.zoom, 4)

        viewport.adjustZoom(by: -20)
        XCTAssertEqual(viewport.zoom, 1)
        XCTAssertEqual(viewport.center, CGPoint(x: 0.5, y: 0.5))

        viewport.adjustZoom(by: 1)
        viewport.reset()
        XCTAssertEqual(viewport, ScreenCaptureViewport())
    }

    func testScrollDirectionAndDevicePrecisionProduceStableZoomAdjustments() {
        XCTAssertEqual(
            ScreenCaptureViewport.zoomAdjustment(scrollingDeltaY: 10, precise: true),
            -0.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ScreenCaptureViewport.zoomAdjustment(scrollingDeltaY: -10, precise: true),
            0.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ScreenCaptureViewport.zoomAdjustment(scrollingDeltaY: 3, precise: false),
            -0.25
        )
        XCTAssertEqual(
            ScreenCaptureViewport.zoomAdjustment(scrollingDeltaY: -3, precise: false),
            0.25
        )
    }

    func testPinchMagnificationUsesNativeGestureDirection() {
        XCTAssertEqual(ScreenCaptureViewport.magnificationAdjustment(0.18), 0.18)
        XCTAssertEqual(ScreenCaptureViewport.magnificationAdjustment(-0.12), -0.12)
        XCTAssertEqual(ScreenCaptureViewport.magnificationAdjustment(0.00001), 0)
    }

    func testCroppedImageIsNormalizedToZeroOrigin() {
        let source = CIImage(color: .red)
            .cropped(to: CGRect(x: 100, y: 50, width: 1920, height: 1080))
        let viewport = ScreenCaptureViewport(zoom: 2, center: CGPoint(x: 0.75, y: 0.25))

        let cropped = viewport.cropped(source)

        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 960, height: 540))
    }
}
