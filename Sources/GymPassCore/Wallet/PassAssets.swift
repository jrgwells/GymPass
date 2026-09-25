import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText
import GymPassShared

/// Generates the PNG assets required by a Wallet pass using Core Graphics, so
/// the repository needs no binary image files and the app needs no asset
/// catalog (which would require Xcode's `actool`).
public enum PassAssetRenderer {
    public struct Style: Sendable {
        public var background: CGColor
        public var foreground: CGColor
        public var label: CGColor
        public init(background: CGColor, foreground: CGColor, label: CGColor) {
            self.background = background
            self.foreground = foreground
            self.label = label
        }
    }

    public static func assets(appearance: PassAppearance) -> [String: Data] {
        let background = color(from: appearance.backgroundHex, fallback: (0.42, 0.21, 0.83))
        let foreground = color(from: appearance.foregroundHex, fallback: (1, 1, 1))
        let style = Style(background: background, foreground: foreground, label: foreground)

        var files: [String: Data] = [:]
        files["icon.png"] = icon(size: 29, style: style) ?? Data()
        files["icon@2x.png"] = icon(size: 58, style: style) ?? Data()
        files["icon@3x.png"] = icon(size: 87, style: style) ?? Data()
        files["logo.png"] = logo(size: CGSize(width: 160, height: 50), scale: 1, title: appearance.title, style: style) ?? Data()
        files["logo@2x.png"] = logo(size: CGSize(width: 160, height: 50), scale: 2, title: appearance.title, style: style) ?? Data()
        files["thumbnail.png"] = glyphImage(size: CGSize(width: 90, height: 90), scale: 1, style: style) ?? Data()
        files["thumbnail@2x.png"] = glyphImage(size: CGSize(width: 90, height: 90), scale: 2, style: style) ?? Data()
        files["strip.png"] = strip(width: 375, height: 123, scale: 1, style: style) ?? Data()
        files["strip@2x.png"] = strip(width: 375, height: 123, scale: 2, style: style) ?? Data()
        return files.filter { !$0.value.isEmpty }
    }

    public static func color(from hex: String, fallback: (Double, Double, Double)) -> CGColor {
        let rgb = HexColor.rgb(from: hex) ?? RGB(red: fallback.0, green: fallback.1, blue: fallback.2)
        return CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    // MARK: - Drawing

    private static func makeContext(size: CGSize, scale: Int) -> CGContext? {
        let width = Int(size.width) * scale
        let height = Int(size.height) * scale
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.interpolationQuality = .high
        return context
    }

    private static func png(from context: CGContext, size: CGSize, scale: Int) -> Data? {
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func icon(size: CGFloat, style: Style) -> Data? {
        guard let context = makeContext(size: CGSize(width: size, height: size), scale: 1) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.23
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(style.background)
        context.fillPath()
        drawGlyph(in: context, rect: rect.insetBy(dx: size * 0.22, dy: size * 0.26), color: style.foreground)
        return png(from: context, size: CGSize(width: size, height: size), scale: 1)
    }

    private static func glyphImage(size: CGSize, scale: Int, style: Style) -> Data? {
        guard let context = makeContext(size: size, scale: scale) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 14, cornerHeight: 14, transform: nil))
        context.setFillColor(style.background)
        context.fillPath()
        drawGlyph(in: context, rect: rect.insetBy(dx: size.width * 0.24, dy: size.height * 0.3), color: style.foreground)
        return png(from: context, size: size, scale: scale)
    }

    private static func logo(size: CGSize, scale: Int, title: String, style: Style) -> Data? {
        guard let context = makeContext(size: size, scale: scale) else { return nil }
        drawGlyph(in: context, rect: CGRect(x: 6, y: size.height / 2 - 10, width: 34, height: 20), color: style.foreground)
        drawText(title.uppercased(), at: CGPoint(x: 48, y: size.height / 2 - 9), fontSize: 20, color: style.foreground, tracking: 1.5, context: context)
        return png(from: context, size: size, scale: scale)
    }

    private static func strip(width: CGFloat, height: CGFloat, scale: Int, style: Style) -> Data? {
        guard let context = makeContext(size: CGSize(width: width, height: height), scale: scale) else { return nil }
        context.setFillColor(style.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Subtle diagonal sheen, drawn once (not animated anywhere).
        context.saveGState()
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06))
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: height))
        context.addLine(to: CGPoint(x: width * 0.5, y: height))
        context.addLine(to: CGPoint(x: width * 0.3, y: 0))
        context.addLine(to: CGPoint(x: 0, y: 0))
        context.closePath()
        context.fillPath()
        context.restoreGState()
        drawGlyph(in: context, rect: CGRect(x: width / 2 - 36, y: height / 2 - 18, width: 72, height: 36), color: style.foreground)
        return png(from: context, size: CGSize(width: width, height: height), scale: scale)
    }

    /// The GymPass mark: a pass silhouette containing two bars.
    private static func drawGlyph(in context: CGContext, rect: CGRect, color: CGColor) {
        context.setStrokeColor(color)
        context.setLineWidth(max(2, rect.height * 0.11))
        context.setLineCap(.round)
        let outer = CGPath(roundedRect: rect, cornerWidth: rect.height * 0.28, cornerHeight: rect.height * 0.28, transform: nil)
        context.addPath(outer)
        context.strokePath()

        let barHeight = max(2, rect.height * 0.12)
        let barInset = rect.width * 0.24
        let bars = [
            CGRect(x: rect.minX + barInset * 0.7, y: rect.midY - barHeight - rect.height * 0.04, width: rect.width - (barInset * 1.4), height: barHeight),
            CGRect(x: rect.minX + barInset, y: rect.midY + rect.height * 0.04, width: rect.width - (barInset * 2), height: barHeight),
        ]
        context.setFillColor(color)
        for bar in bars {
            context.addPath(CGPath(roundedRect: bar, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
            context.fillPath()
        }
    }

    private static func drawText(_ text: String, at point: CGPoint, fontSize: CGFloat, color: CGColor, tracking: CGFloat, context: CGContext) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
