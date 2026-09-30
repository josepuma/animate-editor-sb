import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// The spotlight cone, read back the way the renderer decodes it.
///
/// Core Graphics only — no `MTLDevice` — so unlike `BuiltInTextureTests` this
/// suite runs on a hosted runner too. What it guards is the conversion from the
/// mapper's picture (grey light on opaque black) to the convention every
/// built-in follows: white, with the light carried in alpha.
@Suite("Strobe texture")
struct StrobeTextureTests {
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// Premultiplied RGBA, as the atlas path decodes it.
        func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }

        func alpha(_ x: Int, _ y: Int) -> Int { rgba(x, y).a }
    }

    private func decode() throws -> Pixels {
        let data = try #require(BuiltInTextures.data(for: BuiltInSprite.strobe))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return Pixels(width: width, height: height, bytes: bytes)
    }

    @Test("the texture is named the same on both sides of the layer boundary")
    func pathsAgree() {
        #expect(BuiltInSprite.strobe == "__builtin__/strobe.png")
        #expect(BuiltInTextures.Texture.strobe.path == BuiltInSprite.strobe)
        #expect(BuiltInTextures.Texture.strobe.title == "Spotlight")
        #expect(BuiltInSprite.textures.contains(BuiltInSprite.strobe))
        #expect(BuiltInSprite.isKnown(BuiltInSprite.strobe))
    }

    /// Kept at the source's own size: the atlas shelf-packs any size, and the
    /// scale factor a mapper needs is this number, so it is pinned.
    @Test("it decodes at the size of the source picture")
    func decodesAtSourceSize() throws {
        let pixels = try decode()

        #expect(pixels.width == 255)
        #expect(pixels.height == 248)
    }

    /// The whole point of the conversion: an opaque black background would draw
    /// a black rectangle in normal blend mode. Premultiplied white means
    /// r = g = b = a, so this fails if any colour survived.
    @Test("it is white wherever it has ink")
    func isWhite() throws {
        let pixels = try decode()
        var inked = 0

        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let p = pixels.rgba(x, y)
                guard p.a > 0 else { continue }
                inked += 1
                #expect(
                    abs(p.r - p.a) <= 1 && abs(p.g - p.a) <= 1 && abs(p.b - p.a) <= 1,
                    "(\(x), \(y)) is not white: \(p)",
                )
            }
        }
        #expect(inked > 1000, "an all-transparent image is trivially white")
    }

    /// Where the source's black background was, and where the cone fades out
    /// sideways: nothing there, so linear filtering has nothing to bleed.
    @Test("its border is transparent")
    func borderIsTransparent() throws {
        let pixels = try decode()
        let last = pixels.height - 1
        var worst = 0

        for x in 0..<pixels.width {
            worst = max(worst, pixels.alpha(x, 0), pixels.alpha(x, last))
        }
        for y in 0..<pixels.height {
            worst = max(worst, pixels.alpha(0, y), pixels.alpha(pixels.width - 1, y))
        }
        #expect(worst <= 4, "the border carries alpha \(worst)")
        #expect(pixels.alpha(0, 0) == 0)
        #expect(pixels.alpha(pixels.width - 1, pixels.height - 1) <= 4)
    }

    /// Normalised so the brightest pixel is fully opaque: skipping it would
    /// cap the beam at the source's own peak (155 of 255) and every use would
    /// need extra opacity to compensate.
    @Test("the brightest pixel is fully opaque and sits at the top centre")
    func brightestIsTheSource() throws {
        let pixels = try decode()
        var best = (x: 0, y: 0, a: -1)

        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.alpha(x, y) > best.a {
                best = (x, y, pixels.alpha(x, y))
            }
        }
        #expect(best.a == 255, "peak alpha is \(best.a)")
        #expect(abs(best.x - pixels.width / 2) <= 8, "brightest at x = \(best.x)")
        #expect(best.y < 32, "brightest at y = \(best.y)")
    }

    /// A beam hangs from its source and thins as it travels, so the axis has to
    /// fall — far from the source, where sampling noise cannot fake it.
    @Test("the light falls off down the axis")
    func fallsOffDownTheCone() throws {
        let pixels = try decode()
        let centre = pixels.width / 2
        let a60 = pixels.alpha(centre, 60)
        let a140 = pixels.alpha(centre, 140)
        let a220 = pixels.alpha(centre, 220)

        #expect(a60 > a140, "y60 \(a60) vs y140 \(a140)")
        #expect(a140 > a220, "y140 \(a140) vs y220 \(a220)")
        #expect(a220 > 0, "the beam should still be visible near its far end")
    }

    /// The cone is wider low down than at the source: it opens downward.
    @Test("the cone opens downward")
    func opensDownward() throws {
        let pixels = try decode()

        func width(at y: Int) -> Int {
            let inked = (0..<pixels.width).filter { pixels.alpha($0, y) > 10 }
            guard let first = inked.first, let last = inked.last else { return 0 }
            return last - first
        }

        #expect(width(at: 40) < width(at: 140))
    }
}
