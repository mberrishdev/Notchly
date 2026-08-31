#!/usr/bin/env swift
// Draws Notchly's app icon at every size the asset catalog wants.
// Run with: swift scripts/generate-icon.swift
// The mark is the panel itself: a notch-shaped slab docked to the right edge of a
// dark display, with the concave flares that give the real panel its silhouette.

import AppKit

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16", 16), ("icon_16@2x", 32),
    ("icon_32", 32), ("icon_32@2x", 64),
    ("icon_128", 128), ("icon_128@2x", 256),
    ("icon_256", 256), ("icon_256@2x", 512),
    ("icon_512", 512), ("icon_512@2x", 1024)
]

func notchPath(rect: CGRect, corner: CGFloat, inverse: CGFloat) -> NSBezierPath {
    // Docked to the right edge: rounded on the left, flaring outward on the right.
    let path = NSBezierPath()
    let (x0, x1) = (rect.minX, rect.maxX)
    let (y0, y1) = (rect.minY, rect.maxY)
    path.move(to: CGPoint(x: x1, y: y1))
    path.curve(to: CGPoint(x: x1 - inverse, y: y1 - inverse),
               controlPoint1: CGPoint(x: x1 - inverse, y: y1),
               controlPoint2: CGPoint(x: x1 - inverse, y: y1))
    path.line(to: CGPoint(x: x0 + corner, y: y1 - inverse))
    path.curve(to: CGPoint(x: x0, y: y1 - inverse - corner),
               controlPoint1: CGPoint(x: x0, y: y1 - inverse),
               controlPoint2: CGPoint(x: x0, y: y1 - inverse))
    path.line(to: CGPoint(x: x0, y: y0 + inverse + corner))
    path.curve(to: CGPoint(x: x0 + corner, y: y0 + inverse),
               controlPoint1: CGPoint(x: x0, y: y0 + inverse),
               controlPoint2: CGPoint(x: x0, y: y0 + inverse))
    path.line(to: CGPoint(x: x1 - inverse, y: y0 + inverse))
    path.curve(to: CGPoint(x: x1, y: y0),
               controlPoint1: CGPoint(x: x1 - inverse, y: y0),
               controlPoint2: CGPoint(x: x1 - inverse, y: y0))
    path.close()
    return path
}

func render(pixels: Int) -> Data? {
    let side = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icons sit inside a squircle with a margin around it.
    let inset = side * 0.09
    let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let plateRadius = plate.width * 0.2237
    let squircle = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

    NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
                        NSColor(srgbRed: 0.04, green: 0.045, blue: 0.06, alpha: 1)])?
        .draw(in: squircle, angle: -90)

    squircle.addClip()

    // The panel, docked to the right of the plate.
    let panelWidth = plate.width * 0.30
    let panelHeight = plate.height * 0.52
    let panel = CGRect(x: plate.maxX - panelWidth,
                       y: plate.midY - panelHeight / 2,
                       width: panelWidth, height: panelHeight)
    let corner = panelWidth * 0.42
    let inverse = panelWidth * 0.22

    let shape = notchPath(rect: panel, corner: corner, inverse: inverse)
    NSGradient(colors: [NSColor(srgbRed: 0.55, green: 0.68, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.36, green: 0.51, blue: 0.95, alpha: 1)])?
        .draw(in: shape, angle: -90)

    // Two content lines, hinting at the widget stack inside.
    NSColor(white: 1, alpha: 0.30).setFill()
    let lineHeight = max(1, plate.height * 0.035)
    for (index, width) in [0.30, 0.20].enumerated() {
        let bar = CGRect(x: plate.minX + plate.width * 0.16,
                         y: plate.midY + (index == 0 ? lineHeight * 0.9 : -lineHeight * 2.1),
                         width: plate.width * width, height: lineHeight)
        NSBezierPath(roundedRect: bar, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }

    // Top highlight so the plate reads as glass rather than flat paint.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])?
        .draw(in: CGRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let output = URL(fileURLWithPath: "Notchly/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for entry in sizes {
    guard let data = render(pixels: entry.pixels) else { continue }
    try? data.write(to: output.appendingPathComponent("\(entry.name).png"))
}
print("Wrote \(sizes.count) icon files to \(output.path)")
