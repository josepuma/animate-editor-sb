import CoreGraphics
import Foundation
import ImageIO
import PixelKernels
import StoryboardCore

/// The images behind the Look filters: outline, halftone, duotone and ink.
///
/// Decoding and encoding here; the per-pixel work in `PixelKernels`, a target
/// compiled with optimisation even in debug — see it for why. No Core Image,
/// so every one is exact and testable without a GPU, which a CI runner lacks.
enum LookTextures {
    // ─── Outline ─────────────────────────────────────────────────────────────

    /// The source's silhouette grown by `width`, white, on a canvas grown by
    /// the margin Core undoes when it places the copy.
    ///
    /// Grown by true distance, so corners round: a box-shaped dilation reads
    /// as a chunky offset rather than a line drawn around the shape.
    static func outline(_ data: Data, width: Int) -> Data? {
        guard let image = decode(data) else { return nil }
        let margin = DerivedSprite.outlineMargin(width: Double(width))
        guard var pixels = Pixels(image: image, padding: margin) else { return nil }

        // One pixel of falloff past the width, for an antialiased edge; the
        // silhouette itself stays filled.
        PixelKernels.outline(&pixels.bytes, width: pixels.width, height: pixels.height, reach: Double(width) + 0.5)
        return pixels.encoded()
    }

    // ─── Halftone ────────────────────────────────────────────────────────────

    /// One white dot per `cell` pixels, its area proportional to the cell's
    /// ink — alpha times luminance, so a dim region screens lighter.
    static func halftone(_ data: Data, cell: Int, shape: DerivedSprite.DotShape) -> Data? {
        guard let image = decode(data), let pixels = Pixels(image: image, padding: 0),
              let context = DerivedTextures.bitmap(width: pixels.width, height: pixels.height)
        else { return nil }

        context.setAllowsAntialiasing(true)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        let (fills, columns, rows) = PixelKernels.cellInk(pixels.bytes, width: pixels.width, height: pixels.height, cell: cell)
        for row in 0..<rows {
            for column in 0..<columns {
                let fill = fills[row * columns + column]
                guard fill > 0.004 else { continue }

                // Area, not radius, follows the ink: that is what makes a
                // screen read as a grey level. Full ink reaches the cell's
                // corners, so solid regions close up as print does.
                let side = Double(cell) * fill.squareRoot()
                let size = shape == .round ? side * 2.squareRoot() : side
                let centreX = (Double(column) + 0.5) * Double(cell)
                // CG's y grows upward; rows count from the top.
                let centreY = Double(pixels.height) - (Double(row) + 0.5) * Double(cell)
                let rect = CGRect(x: centreX - size / 2, y: centreY - size / 2, width: size, height: size)
                switch shape {
                case .round: context.fillEllipse(in: rect)
                case .square: context.fill(rect)
                }
            }
        }
        guard let made = context.makeImage() else { return nil }
        return DerivedTextures.encode(made)
    }

    // ─── Duotone ─────────────────────────────────────────────────────────────

    /// Each pixel's luminance mapped from `dark` to `light`, alpha kept.
    static func duotone(_ data: Data, dark: Int, light: Int) -> Data? {
        guard let image = decode(data), var pixels = Pixels(image: image, padding: 0) else { return nil }
        PixelKernels.duotone(&pixels.bytes, count: pixels.width * pixels.height, from: channels(dark), to: channels(light))
        return pixels.encoded()
    }

    // ─── Ink ─────────────────────────────────────────────────────────────────

    /// White lines `width` wide along the silhouette's contour and, as far as
    /// `detail` allows, along the edges inside it.
    ///
    /// The canvas stays the source's size, so the anchor stays put; a line on
    /// the very border of the picture loses its outer half, which only matters
    /// for an image whose ink touches its own edge.
    static func ink(_ data: Data, width: Int, detail: Double) -> Data? {
        guard let image = decode(data), var pixels = Pixels(image: image, padding: 0) else { return nil }
        // Sobel peaks at 4 on a 0–1 step; full detail draws faint edges, a
        // little detail only the strong ones, none the contour alone.
        PixelKernels.ink(
            &pixels.bytes, width: pixels.width, height: pixels.height,
            reach: Double(width) / 2 + 0.5, threshold: detail > 0 ? 0.2 + (1 - detail) * 3.6 : nil,
        )
        return pixels.encoded()
    }

    // ─── Tile ────────────────────────────────────────────────────────────────

    /// One cell of a grid over the source, everything else cleared, on the
    /// source's own canvas. Cell edges are whole pixels and the cells tile
    /// the canvas exactly, so the pieces of a shatter add back up to the
    /// original with no seam and no overlap.
    static func tile(_ data: Data, columns: Int, rows: Int, index: Int) -> Data? {
        guard let image = decode(data), var pixels = Pixels(image: image, padding: 0) else { return nil }
        let column = index % max(columns, 1)
        let row = index / max(columns, 1)
        let left = pixels.width * column / columns
        let right = pixels.width * (column + 1) / columns
        let top = pixels.height * row / rows
        let bottom = pixels.height * (row + 1) / rows
        PixelKernels.clear(&pixels.bytes, width: pixels.width, height: pixels.height, keeping: (left, right, top, bottom))
        return pixels.encoded()
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func channels(_ hex: Int) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// A premultiplied RGBA canvas, with the source drawn at a whole-pixel
/// padding. Memory row 0 is the top of the picture.
private struct Pixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init?(image: CGImage, padding: Int) {
        // Locals, not `self`: the closure below runs before every property
        // is set, and Swift will not let it capture a half-built value.
        let w = image.width + padding * 2
        let h = image.height + padding * 2
        guard w > 0, h > 0 else { return nil }
        width = w
        height = h
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer
    }

    func encoded() -> Data? {
        var buffer = bytes
        let image: CGImage? = buffer.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )?.makeImage()
        }
        return image.flatMap(DerivedTextures.encode)
    }
}
