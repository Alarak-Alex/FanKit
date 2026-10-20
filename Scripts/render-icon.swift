import AppKit
import CoreGraphics
import Foundation

/// Renders the FanKit app icon at every size macOS needs and writes an `.icns`.
///
/// Drawing the icon instead of shipping a bitmap keeps it crisp at 16 pt and
/// lets the palette match the app's accent colour.
///
///     swift Scripts/render-icon.swift Resources

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

func drawIcon(in context: CGContext, size: CGFloat) {
    let scale = size / 1024.0
    context.saveGState()
    context.scaleBy(x: scale, y: scale)

    // macOS icons sit inside a rounded square with a fixed margin.
    let inset: CGFloat = 64
    let rect = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let corner = rect.width * 0.2237
    let shape = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner,
                       transform: nil)

    // Drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18),
                      blur: 42,
                      color: color(0x000000, alpha: 0.45))
    context.addPath(shape)
    context.setFillColor(color(0x0b1020))
    context.fillPath()
    context.restoreGState()

    // Background wash.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [color(0x1a2547), color(0x080b16)] as CFArray,
                                locations: [0, 1])!
    context.drawLinearGradient(background,
                               start: CGPoint(x: rect.midX, y: rect.maxY),
                               end: CGPoint(x: rect.midX, y: rect.minY),
                               options: [])
    context.restoreGState()

    // Soft cyan glow behind the impeller.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0x2fa8ff, alpha: 0.42),
                                   color(0x2fa8ff, alpha: 0.0)] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow,
                               startCenter: CGPoint(x: 512, y: 500), startRadius: 40,
                               endCenter: CGPoint(x: 512, y: 500), endRadius: 400,
                               options: [])
    context.restoreGState()

    let center = CGPoint(x: 512, y: 508)

    // Airflow ring with a warm arc marking the exhaust side.
    let ringRadius: CGFloat = 330
    context.setLineWidth(16)
    context.setLineCap(.round)
    context.setStrokeColor(color(0x63d2ff, alpha: 0.30))
    context.addArc(center: center, radius: ringRadius,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    context.setStrokeColor(color(0xff8a3d, alpha: 0.95))
    context.addArc(center: center, radius: ringRadius,
                   startAngle: -.pi * 0.32, endAngle: -.pi * 0.02, clockwise: false)
    context.strokePath()

    // Five curved blades.
    let bladeCount = 5
    for index in 0..<bladeCount {
        let baseAngle = CGFloat(index) / CGFloat(bladeCount) * .pi * 2
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: baseAngle)

        let hubRadius: CGFloat = 74
        let tipRadius: CGFloat = 268

        let blade = CGMutablePath()
        // Leading edge sweeps forward and outward; the trailing edge is concave
        // so the silhouette reads as a propeller rather than a petal.
        blade.move(to: CGPoint(x: hubRadius - 4, y: -26))
        blade.addCurve(to: CGPoint(x: tipRadius, y: -26),
                       control1: CGPoint(x: hubRadius + 96, y: -132),
                       control2: CGPoint(x: tipRadius - 76, y: -122))
        blade.addCurve(to: CGPoint(x: tipRadius - 16, y: 8),
                       control1: CGPoint(x: tipRadius + 8, y: -14),
                       control2: CGPoint(x: tipRadius - 2, y: -1))
        blade.addCurve(to: CGPoint(x: hubRadius + 2, y: 30),
                       control1: CGPoint(x: tipRadius - 82, y: 58),
                       control2: CGPoint(x: hubRadius + 74, y: 92))
        blade.closeSubpath()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6),
                          blur: 16,
                          color: color(0x000000, alpha: 0.35))
        context.addPath(blade)
        context.clip()
        let bladeGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0x8ef0ff, alpha: 0.98),
                     color(0x2f8dff, alpha: 0.92),
                     color(0x1b4fd6, alpha: 0.82)] as CFArray,
            locations: [0, 0.55, 1]
        )!
        context.drawLinearGradient(
            bladeGradient,
            start: CGPoint(x: hubRadius, y: 60),
            end: CGPoint(x: tipRadius, y: -50),
            options: []
        )
        // Bright leading edge.
        context.setStrokeColor(color(0xd6f8ff, alpha: 0.55))
        context.setLineWidth(3)
        context.strokePath()
        context.restoreGState()

        // Blade outline for definition.
        context.addPath(blade)
        context.setStrokeColor(color(0xbde9ff, alpha: 0.22))
        context.setLineWidth(2)
        context.strokePath()

        context.restoreGState()
    }

    // Metal hub.
    let hubRect = CGRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22,
                      color: color(0x000000, alpha: 0.45))
    context.addEllipse(in: hubRect)
    context.clip()
    let hubGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xe8f6ff), color(0x9fb6cc), color(0x51667d)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(hubGradient,
                               start: CGPoint(x: hubRect.minX, y: hubRect.maxY),
                               end: CGPoint(x: hubRect.maxX, y: hubRect.minY),
                               options: [])
    context.restoreGState()

    context.addEllipse(in: hubRect)
    context.setStrokeColor(color(0xffffff, alpha: 0.30))
    context.setLineWidth(2)
    context.strokePath()

    context.setFillColor(color(0x16233a, alpha: 0.85))
    context.fillEllipse(in: hubRect.insetBy(dx: 46, dy: 46))

    // Top highlight across the tile for the glass feel.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(0xffffff, alpha: 0.14),
                                    color(0xffffff, alpha: 0.0)] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY),
        options: []
    )
    context.restoreGState()

    // Hairline border.
    context.addPath(shape)
    context.setStrokeColor(color(0xffffff, alpha: 0.16))
    context.setLineWidth(3)
    context.strokePath()

    context.restoreGState()
}

func renderPNG(size: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil,
                                  width: size,
                                  height: size,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    drawIcon(in: context, size: CGFloat(size))

    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

// MARK: - Entry point

let outputRoot = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "Resources")

let iconset = outputRoot.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The iconset needs both 1x and 2x renders for every slot.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    try renderPNG(size: variant.pixels,
                  to: iconset.appendingPathComponent("\(variant.name).png"))
}

try renderPNG(size: 1024, to: outputRoot.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path,
                      "-o", outputRoot.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    try? FileManager.default.removeItem(at: iconset)
    print("Wrote \(outputRoot.appendingPathComponent("AppIcon.icns").path)")
} else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
