import XCTest
import CoreImage
@testable import Ping

final class PIPCompositorTests: XCTestCase {
    func test_compose_putsFaceInBottomRightWithCircleMask() {
        let screenSize = CGSize(width: 1920, height: 1080)
        let faceSize = CGSize(width: 1080, height: 1080)
        let screen = CIImage(color: .red).cropped(to: CGRect(origin: .zero, size: screenSize))
        let face = CIImage(color: .green).cropped(to: CGRect(origin: .zero, size: faceSize))

        let composed = PIPCompositor.compose(screen: screen, face: face, outputSize: screenSize, faceDiameterRatio: 0.18, paddingRatio: 0.03)

        XCTAssertEqual(composed.extent.size, screenSize)

        let context = CIContext()
        let cgImage = context.createCGImage(composed, from: composed.extent)!
        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        // Face circle is in bottom-right of CI coordinates.
        // Diameter ≈ 1080 * 0.18 = 194.4. Padding ≈ 1080 * 0.03 = 32.4.
        // faceOriginX (CI) = 1920 - 32.4 - 194.4 = 1693.2
        // faceOriginY (CI) = 32.4
        // Face center CI (bottom-left origin):
        //   x_ci = 1693.2 + 194.4/2 ≈ 1790
        //   y_ci = 32.4 + 194.4/2 ≈ 130
        // NSBitmapImageRep uses top-left:
        //   y_top = 1080 - 130 = 950
        let centerInsideFace = bitmap.colorAt(x: 1790, y: 950)
        XCTAssertNotNil(centerInsideFace)
        XCTAssertGreaterThan(centerInsideFace!.greenComponent, 0.5)
        XCTAssertLessThan(centerInsideFace!.redComponent, 0.5)

        // Top-left is outside face PIP → should be screen color (red).
        let topLeft = bitmap.colorAt(x: 100, y: 100)
        XCTAssertNotNil(topLeft)
        XCTAssertGreaterThan(topLeft!.redComponent, 0.5)
    }
}
