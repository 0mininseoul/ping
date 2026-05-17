import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Resources/AppIcon.png")
let assetRoot = root.appendingPathComponent("Ping/Assets.xcassets")
let appIconSet = assetRoot.appendingPathComponent("AppIcon.appiconset")
let menuSet = assetRoot.appendingPathComponent("MenuBarIcon.imageset")
let headerSet = assetRoot.appendingPathComponent("HeaderLogo.imageset")

guard let source = NSImage(contentsOf: sourceURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Resources/AppIcon.png is missing or unreadable.")
}

try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: headerSet, withIntermediateDirectories: true)

func pngData(from image: NSImage, size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap representation.")
    }

    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero,
               operation: .sourceOver,
               fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG.")
    }
    return data
}

func roundedIconImage(from cgImage: CGImage) -> NSImage {
    let width = cgImage.width
    let height = cgImage.height
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create source bitmap.")
    }

    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height),
              from: .zero,
              operation: .copy,
              fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let rect = CGRect(
        x: Double(width) * 0.102,
        y: Double(height) * 0.102,
        width: Double(width) * 0.796,
        height: Double(height) * 0.796
    )
    let radius = Double(width) * 0.132
    let smoothing = Double(width) * 0.012

    guard let bytes = rep.bitmapData else {
        fatalError("Source bitmap has no pixel data.")
    }

    for y in 0..<height {
        for x in 0..<width {
            let px = Double(x) + 0.5
            let py = Double(y) + 0.5
            let qx = abs(px - rect.midX) - rect.width / 2 + radius
            let qy = abs(py - rect.midY) - rect.height / 2 + radius
            let outsideDistance = hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius
            let alpha: UInt8

            if outsideDistance <= -smoothing {
                alpha = 255
            } else if outsideDistance >= smoothing {
                alpha = 0
            } else {
                let t = 1 - ((outsideDistance + smoothing) / (2 * smoothing))
                alpha = UInt8(max(0, min(255, round(t * 255))))
            }

            let offset = y * rep.bytesPerRow + x * 4
            bytes[offset + 3] = alpha
            if alpha == 0 {
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
            }
        }
    }

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(rep)
    return image
}

func writeMenuBarLensIcon(size: Int, filename: String) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create menu icon bitmap.")
    }

    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let scale = CGFloat(size) / 18
    let fullSize = CGFloat(size)
    let iconRect = NSRect(
        x: 2.1 * scale,
        y: 2.1 * scale,
        width: fullSize - 4.2 * scale,
        height: fullSize - 4.2 * scale
    )
    let center = NSPoint(x: fullSize / 2, y: fullSize / 2)

    let lensOuterRing = NSBezierPath(ovalIn: iconRect)
    let lensShadow = NSShadow()
    lensShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.22)
    lensShadow.shadowOffset = NSSize(width: 0, height: -0.55 * scale)
    lensShadow.shadowBlurRadius = 1.5 * scale
    lensShadow.set()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.36, blue: 0.39, alpha: 0.98),
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 0.98)
    ])?.draw(in: lensOuterRing, angle: 270)
    NSShadow().set()

    NSColor(calibratedWhite: 1.0, alpha: 0.42).setStroke()
    lensOuterRing.lineWidth = 0.72 * scale
    lensOuterRing.stroke()

    let innerRect = iconRect.insetBy(dx: 2.65 * scale, dy: 2.65 * scale)
    let innerLens = NSBezierPath(ovalIn: innerRect)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.17, alpha: 1.0),
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1.0)
    ])?.draw(in: innerLens, angle: 250)
    NSColor(calibratedWhite: 0.75, alpha: 0.20).setStroke()
    innerLens.lineWidth = 0.85 * scale
    innerLens.stroke()

    let upperHighlight = NSBezierPath()
    upperHighlight.lineCapStyle = .round
    upperHighlight.lineWidth = 0.85 * scale
    upperHighlight.appendArc(
        withCenter: center,
        radius: 5.15 * scale,
        startAngle: 54,
        endAngle: 126
    )
    NSColor.white.withAlphaComponent(0.56).setStroke()
    upperHighlight.stroke()

    let blueCatchlight = NSBezierPath()
    blueCatchlight.lineCapStyle = .round
    blueCatchlight.lineWidth = 1.05 * scale
    blueCatchlight.appendArc(
        withCenter: center,
        radius: 5.2 * scale,
        startAngle: 286,
        endAngle: 344
    )
    NSColor(calibratedRed: 0.24, green: 0.58, blue: 1.0, alpha: 0.94).setStroke()
    blueCatchlight.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode menu icon PNG.")
    }
    try data.write(to: menuSet.appendingPathComponent(filename), options: .atomic)
}

let roundedIcon = roundedIconImage(from: sourceCG)
let appImages: [(String, Int)] = [
    ("app-icon-16.png", 16),
    ("app-icon-32.png", 32),
    ("app-icon-64.png", 64),
    ("app-icon-128.png", 128),
    ("app-icon-256.png", 256),
    ("app-icon-512.png", 512),
    ("app-icon-1024.png", 1024)
]

for (filename, size) in appImages {
    try pngData(from: roundedIcon, size: size)
        .write(to: appIconSet.appendingPathComponent(filename), options: .atomic)
}

try writeMenuBarLensIcon(size: 18, filename: "menubar-icon.png")
try writeMenuBarLensIcon(size: 36, filename: "menubar-icon@2x.png")
try Data(contentsOf: sourceURL)
    .write(to: headerSet.appendingPathComponent("header-logo.png"), options: .atomic)

let appIconContents = """
{
  "images" : [
    { "filename" : "app-icon-16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "app-icon-32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "app-icon-32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "app-icon-64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "app-icon-128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "app-icon-256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "app-icon-256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "app-icon-512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "app-icon-512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "app-icon-1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

let menuContents = """
{
  "images" : [
    { "filename" : "menubar-icon.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "menubar-icon@2x.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

let headerContents = """
{
  "images" : [
    { "filename" : "header-logo.png", "idiom" : "universal", "scale" : "1x" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try appIconContents.write(to: appIconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try menuContents.write(to: menuSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try headerContents.write(to: headerSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try rootContents.write(to: assetRoot.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
