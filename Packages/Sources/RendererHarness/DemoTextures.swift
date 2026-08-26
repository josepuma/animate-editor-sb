import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds the demo's sprite images in memory, so the preview needs no assets.
enum DemoTextures {
    /// PNG data for a demo sprite path, or `nil` when the path is unknown.
    static func png(for path: String) -> Data? {
        switch path {
        case "circle.png": encode(drawCircle(size: 128))
        case "square.png": encode(drawSquare(size: 128))
        default: nil
        }
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    /// A soft radial dot. Premultiplied, so it composites correctly under both
    /// blend modes.
    private static func drawCircle(size: Int) -> CGImage? {
        guard let context = makeContext(size: size) else { return nil }
        let extent = CGFloat(size)
        let centre = CGPoint(x: extent / 2, y: extent / 2)

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.85),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray,
            locations: [0, 0.55, 1],
        ) else { return nil }

        context.drawRadialGradient(
            gradient,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: extent / 2,
            options: [],
        )
        return context.makeImage()
    }

    /// A rounded square with a brighter rim, so rotation and mirroring are easy
    /// to see on screen.
    private static func drawSquare(size: Int) -> CGImage? {
        guard let context = makeContext(size: size) else { return nil }
        let extent = CGFloat(size)
        let inset: CGFloat = extent * 0.12
        let rect = CGRect(x: inset, y: inset, width: extent - inset * 2, height: extent - inset * 2)
        let path = CGPath(roundedRect: rect, cornerWidth: extent * 0.18, cornerHeight: extent * 0.18, transform: nil)

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        context.addPath(path)
        context.fillPath()

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(extent * 0.06)
        context.addPath(path)
        context.strokePath()

        // An off-centre notch makes horizontal flips obvious.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(
            x: extent * 0.62, y: extent * 0.44,
            width: extent * 0.16, height: extent * 0.12,
        ))

        return context.makeImage()
    }

    private static func makeContext(size: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
    }

    private static func encode(_ image: CGImage?) -> Data? {
        guard let image else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
