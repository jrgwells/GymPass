#!/usr/bin/env swift
// Generates the GymPass app icon as an .iconset directory using Core Graphics.
// Run with: swift scripts/build-icon.swift <output-iconset-dir>
// The build script then converts it to .icns with iconutil.

import AppKit
import Foundation

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high

    // Rounded-square base with a deep violet gradient.
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [
        CGColor(srgbRed: 0.42, green: 0.20, blue: 0.85, alpha: 1),
        CGColor(srgbRed: 0.30, green: 0.12, blue: 0.62, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    }
    context.restoreGState()

    // Translucent inner pass shape.
    let passRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.24)
    let passCorner = passRect.width * 0.14
    context.addPath(CGPath(roundedRect: passRect, cornerWidth: passCorner, cornerHeight: passCorner, transform: nil))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
    context.fillPath()
    context.addPath(CGPath(roundedRect: passRect, cornerWidth: passCorner, cornerHeight: passCorner, transform: nil))
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
    context.setLineWidth(max(1, size * 0.018))
    context.strokePath()

    // Two bars (scanner + barbell suggestion).
    let barHeight = max(1, size * 0.055)
    let barWidth = passRect.width * 0.62
    let barX = passRect.midX - barWidth / 2
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    for offset in [-0.16, 0.16] as [CGFloat] {
        let bar = CGRect(x: barX, y: passRect.midY + passRect.height * offset - barHeight / 2, width: barWidth, height: barHeight)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
        context.fillPath()
    }

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

for entry in sizes {
    guard let data = drawIcon(pixels: entry.pixels) else {
        FileHandle.standardError.write(Data("Failed to render \(entry.name)\n".utf8))
        exit(1)
    }
    try data.write(to: outputURL.appendingPathComponent(entry.name))
}
print("Wrote iconset to \(outputPath)")
