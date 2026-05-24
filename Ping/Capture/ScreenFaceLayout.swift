import CoreGraphics

enum ScreenFaceLayout {
    static let faceDiameterRatio: CGFloat = 0.32
    static let paddingRatio: CGFloat = 0.045

    static func faceDiameter(in size: CGSize) -> CGFloat {
        shortestSide(in: size) * faceDiameterRatio
    }

    static func padding(in size: CGSize) -> CGFloat {
        shortestSide(in: size) * paddingRatio
    }

    private static func shortestSide(in size: CGSize) -> CGFloat {
        max(0, min(size.width, size.height))
    }
}
