import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing
import UniformTypeIdentifiers

@testable import StoryboardRendering

/// The images behind Outline, Halftone, Duotone and Ink.
///
/// Read with Core Graphics, never the GPU, so they run on CI. Row 0 is the top
/// of the picture. Every test uses a source path of its own: the derived cache
/// is global and keyed by path, and suites run in parallel.
@Suite("Look textures")
struct LookTextureTests {
    private struct Picture {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init(_ data: Data) throws {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &buffer, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func alpha(_ x: Int, _ y: Int) -> Double { Double(bytes[(y * width + x) * 4 + 3]) / 255 }
        /// Un-premultiplied channel, 0–255.
        func channel(_ x: Int, _ y: Int, _ c: Int) -> Double {
            let a = alpha(x, y)
            return a > 0 ? Double(bytes[(y * width + x) * 4 + c]) / a : 0
        }
        func coverage() -> Double {
            var total = 0.0
            for y in 0..<height { for x in 0..<width { total += alpha(x, y) } }
            return total
        }
    }

    /// `size`² canvas with an opaque square of `colour` from `inset` to
    /// `size − inset` on both axes.
    private func square(size: Int, inset: Int, gray: CGFloat = 1) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func render(_ path: String, source: Data) throws -> Picture {
        try Picture(#require(DerivedTextures.data(for: path) { _ in source }))
    }

    private func key() -> String { "src-\(UUID().uuidString).png" }

    // MARK: - Outline

    @Test("the outlined canvas grows by the margin on every side")
    func outlineCanvas() throws {
        let picture = try render(DerivedSprite.outlined(key(), width: 4), source: square(size: 40, inset: 10))
        let margin = DerivedSprite.outlineMargin(width: 4)
        #expect(picture.width == 40 + margin * 2)
        #expect(picture.height == 40 + margin * 2)
    }

    @Test("the ring is solid just outside the silhouette and gone past the width")
    func outlineRing() throws {
        let margin = DerivedSprite.outlineMargin(width: 4)
        let picture = try render(DerivedSprite.outlined(key(), width: 4), source: square(size: 40, inset: 10))
        // The square's left edge sits at x = margin + 10; mid-height row.
        let row = picture.height / 2
        let edge = margin + 10
        #expect(picture.alpha(edge - 2, row) > 0.95, "inside the ring")
        #expect(picture.alpha(edge + 5, row) > 0.95, "the silhouette itself is filled")
        #expect(picture.alpha(edge - 7, row) < 0.05, "past the width")
    }

    /// Round, not square: a corner grown by a distance is an arc, and a
    /// box-shaped dilation reads as a chunky offset rather than a line.
    @Test("the ring rounds the corners")
    func outlineRound() throws {
        let margin = DerivedSprite.outlineMargin(width: 4)
        let picture = try render(DerivedSprite.outlined(key(), width: 4), source: square(size: 40, inset: 10))
        let corner = margin + 10
        // Diagonally 4px out from the corner is ~5.7px away: outside a round ring.
        #expect(picture.alpha(corner - 4, corner - 4) < 0.05)
    }

    // MARK: - Halftone

    @Test("halftone keeps the source's size")
    func halftoneSize() throws {
        let picture = try render(DerivedSprite.halftone(key(), cell: 8, shape: .round), source: square(size: 48, inset: 0))
        #expect(picture.width == 48 && picture.height == 48)
    }

    @Test("a dot grows with the ink in its cell")
    func halftoneGrades() throws {
        let full = try render(DerivedSprite.halftone(key(), cell: 8, shape: .round), source: square(size: 48, inset: 0))
        let dim = try render(DerivedSprite.halftone(key(), cell: 8, shape: .round), source: square(size: 48, inset: 0, gray: 0.25))
        #expect(full.coverage() > dim.coverage() * 2)
        #expect(dim.coverage() > 0)
    }

    @Test("an empty cell draws no dot")
    func halftoneEmpty() throws {
        let picture = try render(DerivedSprite.halftone(key(), cell: 8, shape: .round), source: square(size: 48, inset: 16))
        #expect(picture.alpha(4, 4) == 0)
    }

    // MARK: - Duotone

    @Test("white maps to the highlight and black to the shadow, alpha kept")
    func duotone() throws {
        let dark = EffectColor(r: 30, g: 20, b: 90)
        let light = EffectColor(r: 255, g: 200, b: 90)
        let white = try render(DerivedSprite.duotone(key(), dark: dark, light: light), source: square(size: 20, inset: 4))
        #expect(abs(white.channel(10, 10, 1) - 200) < 3)
        #expect(white.alpha(1, 1) == 0, "transparent stays transparent")

        let black = try render(DerivedSprite.duotone(key(), dark: dark, light: light), source: square(size: 20, inset: 4, gray: 0))
        #expect(abs(black.channel(10, 10, 2) - 90) < 3)
        #expect(abs(black.channel(10, 10, 0) - 30) < 3)
    }

    // MARK: - Ink

    @Test("a flat silhouette inks only its contour")
    func inkContour() throws {
        let picture = try render(DerivedSprite.inked(key(), width: 2, detail: 0.3), source: square(size: 40, inset: 8))
        #expect(picture.width == 40)
        #expect(picture.alpha(8, 20) > 0.9, "the edge is drawn")
        #expect(picture.alpha(20, 20) < 0.05, "a flat interior has no lines")
        #expect(picture.alpha(2, 20) < 0.05, "outside stays empty")
    }

    @Test("detail draws edges inside the silhouette, zero detail does not")
    func inkDetail() throws {
        // A white square inside a black one: one silhouette, one inner edge —
        // the sharpest edge there is, so zero detail has to be what keeps it
        // out, not a threshold it happens to fall under.
        let context = try #require(CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 14, y: 14, width: 12, height: 12))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let detailed = try render(DerivedSprite.inked(key(), width: 2, detail: 0.5), source: data as Data)
        let plain = try render(DerivedSprite.inked(key(), width: 2, detail: 0), source: data as Data)
        #expect(detailed.alpha(14, 20) > 0.9)
        #expect(plain.alpha(14, 20) < 0.05)
    }

    // MARK: - Tile

    @Test("the tiles of a grid add back up to the source, with no seam or overlap")
    func tilesAddUp() throws {
        let source = try square(size: 30, inset: 0)
        let key = key()
        let tiles = try (0..<6).map { try render(DerivedSprite.tiled(key, columns: 3, rows: 2, index: $0), source: source) }
        #expect(tiles.allSatisfy { $0.width == 30 && $0.height == 30 })
        for y in 0..<30 {
            for x in 0..<30 {
                let covered = tiles.map { $0.alpha(x, y) }.filter { $0 > 0.5 }.count
                #expect(covered == 1, "pixel \(x),\(y) covered \(covered) times")
            }
        }
        // Cell 0 is the top-left third by half.
        #expect(tiles[0].alpha(2, 2) > 0.5 && tiles[0].alpha(12, 2) < 0.5 && tiles[0].alpha(2, 17) < 0.5)
    }
}
