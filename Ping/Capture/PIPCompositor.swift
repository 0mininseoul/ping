import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum PIPCompositor {
    static func compose(
        screen: CIImage,
        face: CIImage,
        outputSize: CGSize,
        faceDiameterRatio: CGFloat,
        paddingRatio: CGFloat
    ) -> CIImage {
        let diameter = min(outputSize.width, outputSize.height) * faceDiameterRatio
        let padding = min(outputSize.width, outputSize.height) * paddingRatio

        let scaledFace = scaledToFill(image: face, square: diameter)
        let maskedFace = applyCircularMask(image: scaledFace, diameter: diameter)

        let faceOriginX = outputSize.width - padding - diameter
        let faceOriginY = padding
        let positionedFace = maskedFace.transformed(by: CGAffineTransform(translationX: faceOriginX, y: faceOriginY))

        let composedFull = positionedFace.composited(over: screen)
        return composedFull.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    private static func scaledToFill(image: CIImage, square: CGFloat) -> CIImage {
        let extent = image.extent
        let scale = square / min(extent.width, extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let s = scaled.extent
        let cropOriginX = s.origin.x + (s.width - square) / 2
        let cropOriginY = s.origin.y + (s.height - square) / 2
        return scaled
            .cropped(to: CGRect(x: cropOriginX, y: cropOriginY, width: square, height: square))
            .transformed(by: CGAffineTransform(translationX: -cropOriginX, y: -cropOriginY))
    }

    private static func applyCircularMask(image: CIImage, diameter: CGFloat) -> CIImage {
        let mask = CIFilter.radialGradient()
        mask.center = CGPoint(x: diameter / 2, y: diameter / 2)
        mask.radius0 = Float(diameter / 2 - 1)
        mask.radius1 = Float(diameter / 2)
        mask.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        mask.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let maskImage = mask.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter))

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        blend.maskImage = maskImage
        return blend.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter))
    }
}
