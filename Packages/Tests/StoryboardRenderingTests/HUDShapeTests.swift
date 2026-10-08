import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// The HUD vocabulary: segmented rings, arcs, dashes, ticks and the bracket.
///
/// Core Graphics only, so these run on a CI runner. Coordinates are visual:
/// `y` grows downward and row 0 is the top of the picture.
@Suite("HUD shapes")
struct HUDShapeTests {
    private struct Picture {
        let size: Int
        private let bytes: [UInt8]

        init(_ shape: BuiltInTextures.Shape) throws {
            let data = try #require(BuiltInTextures.data(for: shape.path), "no image for \(shape)")
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            size = image.width
            var buffer = [UInt8](repeating: 0, count: size * size * 4)
            let context = try #require(CGContext(
                data: &buffer, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            bytes = buffer
        }

        func alpha(_ x: Int, _ y: Int) -> Double { Double(bytes[(y * size + x) * 4 + 3]) / 255 }

        /// Where the ink sits, weighted by alpha.
        var centroid: (x: Double, y: Double) {
            var sx = 0.0, sy = 0.0, total = 0.0
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let a = alpha(x, y)
                    sx += Double(x) * a; sy += Double(y) * a; total += a
                }
            }
            return (sx / total, sy / total)
        }
    }

    @Test("Core and the renderer name the same HUD shapes")
    func listsAgree() {
        #expect(Set(BuiltInSprite.hudShapes) == Set(BuiltInTextures.Shape.hud.map(\.path)))
        #expect(BuiltInSprite.hudShapes.allSatisfy(BuiltInSprite.shapes.contains))
    }

    /// Thin curves, drawn large: at 64 a ring of 48 dashes is mush.
    @Test("every HUD shape is drawn at 512", arguments: BuiltInTextures.Shape.hud)
    func drawnLarge(shape: BuiltInTextures.Shape) throws {
        #expect(try Picture(shape).size == 512)
    }

    /// Paint, not light: a hard edge, so only the antialiased texel along a
    /// curve is neither ink nor empty — and a margin, so that texel is not
    /// cut off by the canvas edge.
    @Test("every HUD shape is hard-edged with a margin", arguments: BuiltInTextures.Shape.hud)
    func hardEdgedWithMargin(shape: BuiltInTextures.Shape) throws {
        let picture = try Picture(shape)
        var ink = 0, soft = 0
        for y in 0 ..< picture.size {
            for x in 0 ..< picture.size {
                let a = picture.alpha(x, y)
                if a > 0.1 { ink += 1 }
                if a > 0.1, a < 0.9 { soft += 1 }
            }
        }
        #expect(ink > 1000, "\(shape) draws almost nothing")
        #expect(Double(soft) / Double(ink) < 0.2, "\(shape) has a soft edge: \(soft) of \(ink) pixels")
        for i in 0 ..< picture.size {
            for edge in [0, picture.size - 1] {
                #expect(picture.alpha(i, edge) == 0 && picture.alpha(edge, i) == 0, "\(shape) touches its edge")
            }
        }
    }

    /// A spinning ring turns in place only if it is centred on its canvas —
    /// the sprite turns about its middle.
    @Test("the closed rings are centred on their canvas",
          arguments: [BuiltInTextures.Shape.hudSegments, .hudDashes, .hudTicks])
    func ringsAreCentred(shape: BuiltInTextures.Shape) throws {
        let centre = try Picture(shape).centroid
        #expect(abs(centre.x - 255.5) < 2 && abs(centre.y - 255.5) < 2, "\(shape)'s ink centres at \(centre)")
    }

    /// The bracket sits on top of its circle and is mirror-symmetric, so a
    /// lock built from four of them turned a quarter each closes as a square.
    @Test("the bracket sits on top of its circle, symmetric")
    func bracketSitsOnTop() throws {
        let picture = try Picture(.hudBracket)
        let centre = picture.centroid
        #expect(abs(centre.x - 255.5) < 1.5, "the bracket is off-centre sideways: \(centre.x)")
        #expect(centre.y < 64, "the bracket is not at the top: \(centre.y)")
        for y in 0 ..< picture.size {
            for x in 0 ..< picture.size / 2 {
                #expect(abs(picture.alpha(x, y) - picture.alpha(picture.size - 1 - x, y)) < 0.2,
                        "the bracket is not mirror-symmetric at \(x), \(y)")
                if abs(picture.alpha(x, y) - picture.alpha(picture.size - 1 - x, y)) >= 0.2 { return }
            }
        }
    }
}
