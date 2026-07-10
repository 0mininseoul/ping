import CoreGraphics
import CoreImage

struct ScreenCaptureViewport: Equatable, Sendable {
    static let minimumZoom: CGFloat = 1
    static let maximumZoom: CGFloat = 4

    private(set) var zoom: CGFloat
    private(set) var center: CGPoint

    init(zoom: CGFloat = minimumZoom, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.zoom = Self.clampedZoom(zoom)
        self.center = Self.clampedCenter(center, zoom: self.zoom)
    }

    mutating func adjustZoom(by delta: CGFloat) {
        zoom = Self.clampedZoom(zoom + delta)
        center = Self.clampedCenter(center, zoom: zoom)
    }

    static func zoomAdjustment(scrollingDeltaY: CGFloat, precise: Bool) -> CGFloat {
        guard abs(scrollingDeltaY) > 0.01 else { return 0 }
        if precise {
            return -scrollingDeltaY * 0.0125
        }
        return scrollingDeltaY > 0 ? -0.25 : 0.25
    }

    static func magnificationAdjustment(_ magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite, abs(magnification) > 0.0001 else { return 0 }
        return magnification
    }

    @discardableResult
    mutating func moveCenter(toScreenPoint point: CGPoint, in displayFrame: CGRect) -> Bool {
        guard displayFrame.width > 0,
              displayFrame.height > 0,
              point.x >= displayFrame.minX,
              point.x <= displayFrame.maxX,
              point.y >= displayFrame.minY,
              point.y <= displayFrame.maxY else {
            return false
        }

        let normalized = CGPoint(
            x: (point.x - displayFrame.minX) / displayFrame.width,
            y: (point.y - displayFrame.minY) / displayFrame.height
        )
        center = Self.clampedCenter(normalized, zoom: zoom)
        return true
    }

    mutating func reset() {
        zoom = Self.minimumZoom
        center = CGPoint(x: 0.5, y: 0.5)
    }

    func cropRect(in extent: CGRect) -> CGRect {
        guard extent.width > 0, extent.height > 0 else { return extent }

        let cropSize = CGSize(width: extent.width / zoom, height: extent.height / zoom)
        let centerPoint = CGPoint(
            x: extent.minX + center.x * extent.width,
            y: extent.minY + center.y * extent.height
        )
        return CGRect(
            x: centerPoint.x - cropSize.width / 2,
            y: centerPoint.y - cropSize.height / 2,
            width: cropSize.width,
            height: cropSize.height
        )
    }

    func cropped(_ image: CIImage) -> CIImage {
        let rect = cropRect(in: image.extent)
        return image
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return minimumZoom }
        return min(maximumZoom, max(minimumZoom, zoom))
    }

    private static func clampedCenter(_ center: CGPoint, zoom: CGFloat) -> CGPoint {
        let inset = 0.5 / zoom
        return CGPoint(
            x: min(1 - inset, max(inset, center.x)),
            y: min(1 - inset, max(inset, center.y))
        )
    }
}
