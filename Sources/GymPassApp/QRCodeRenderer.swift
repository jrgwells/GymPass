import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Renders QR codes using Core Image. The GymPass QR is never animated or
/// stylised in a way that could make it harder to scan.
enum QRCodeRenderer {
    private static let context = CIContext()

    static func image(for payload: String, scale: CGFloat = 10) -> NSImage? {
        guard !payload.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}

struct QRCodeView: View {
    let payload: String
    var size: CGFloat = 150

    var body: some View {
        Group {
            if let image = QRCodeRenderer.image(for: payload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "qrcode").font(.title).foregroundStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
    }
}
