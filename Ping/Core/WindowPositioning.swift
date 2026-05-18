import CoreGraphics

enum WindowPositioning {
    static func visibleOrigin(
        preferred: CGPoint?,
        windowSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return .zero
        }

        let candidate = preferred ?? centeredOrigin(windowSize: windowSize, in: visibleFrame)

        return ScreenCoordinates.clamp(
            point: candidate,
            windowSize: windowSize,
            inSafeArea: visibleFrame
        )
    }

    private static func centeredOrigin(windowSize: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    }
}
