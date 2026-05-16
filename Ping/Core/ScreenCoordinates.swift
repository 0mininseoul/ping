import CoreGraphics

enum ScreenCoordinates {
    static func normalize(point: CGPoint, in screen: CGRect) -> MirrorPosition {
        guard screen.width > 0, screen.height > 0 else {
            return MirrorPosition(xRatio: 0.5, yRatio: 0.5)
        }

        return MirrorPosition(
            xRatio: Double((point.x - screen.minX) / screen.width),
            yRatio: Double((point.y - screen.minY) / screen.height)
        )
    }

    static func denormalize(position: MirrorPosition, in screen: CGRect) -> CGPoint {
        CGPoint(
            x: screen.minX + screen.width * CGFloat(position.xRatio),
            y: screen.minY + screen.height * CGFloat(position.yRatio)
        )
    }

    static func clamp(point: CGPoint, windowSize: CGSize, inSafeArea safeArea: CGRect) -> CGPoint {
        let maxX = max(safeArea.minX, safeArea.maxX - windowSize.width)
        let maxY = max(safeArea.minY, safeArea.maxY - windowSize.height)

        return CGPoint(
            x: min(max(point.x, safeArea.minX), maxX),
            y: min(max(point.y, safeArea.minY), maxY)
        )
    }
}
