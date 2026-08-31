#!/usr/bin/env swift
// Draws Notchly's menu bar icon.
// Run with: swift scripts/generate-menubar-icon.swift
//
// Tray icons are template images: macOS keeps only the alpha channel and tints the
// result, so this draws in flat black and never in colour. Tauri scales whatever it
// is given to 18pt tall, so the artwork is authored at 18pt and rendered at 2x.
//
// The mark is a display with a notch docked to its right edge — the app's whole idea
// in one shape, and legible at 18pt where the concave flares of the real panel are not.

import AppKit

let point: CGFloat = 18
let scale: CGFloat = 2
let pixels = Int(point * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
context.scaleBy(x: scale, y: scale)
context.setAllowsAntialiasing(true)

NSColor.black.setStroke()
NSColor.black.setFill()

// The display, as an outline so the notch reads as the solid mark against it.
let stroke: CGFloat = 1.3
let screen = CGRect(x: 1, y: 3.5, width: 16, height: 11).insetBy(dx: stroke / 2, dy: stroke / 2)
let outline = NSBezierPath(roundedRect: screen, xRadius: 2.4, yRadius: 2.4)
outline.lineWidth = stroke
outline.stroke()

// The notch, hanging from the top edge. A tab on the *side* was tried first and read
// as a battery gauge; the top edge is the idiom everyone already recognises.
let notchWidth: CGFloat = 6.4
let notchHeight: CGFloat = 3.2
let notch = CGRect(x: screen.midX - notchWidth / 2,
                   y: screen.maxY - notchHeight,
                   width: notchWidth,
                   height: notchHeight)
NSBezierPath(roundedRect: notch, xRadius: 1.4, yRadius: 1.4).fill()
// Square the top off so it merges into the bezel rather than floating.
NSBezierPath(rect: CGRect(x: notch.minX, y: notch.maxY - 2, width: notchWidth, height: 2)).fill()

NSGraphicsContext.restoreGraphicsState()

let output = URL(fileURLWithPath: "src-tauri/icons/menubar.png")
if let data = rep.representation(using: .png, properties: [:]) {
    try? data.write(to: output)
    print("Wrote \(pixels)x\(pixels) template icon to \(output.path)")
}
