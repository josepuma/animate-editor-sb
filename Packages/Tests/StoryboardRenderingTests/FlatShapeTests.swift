import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import StoryboardRendering
import StoryboardCore

/// The drawn vocabulary of the Flat family: chevrons, arrows, triangles,
/// hazard stripes, vector nodes and plus marks.
///
/// Read with Core Graphics rather than the GPU, so unlike the texture
/// decoding suite these run on a CI runner too. Coordinates here are visual:
/// `y` grows downward and row 0 is the top of the picture, which is the
/// direction a sprite's "up" (0, −1) points.
@Suite("Flat shapes")
struct FlatShapeTests {
    private static let names = ["chevron", "arrow", "triangle", "stripe", "node", "cross"]

    private struct Picture {
        let size: Int
        private let bytes: [UInt8]

        init(name: String) throws {
            let data = try #require(
                BuiltInTextures.data(for: "__builtin__/\(name).png"),
                "no image for \(name)",
            )
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            size = image.width
            #expect(image.height == image.width)

            var buffer = [UInt8](repeating: 0, count: size * size * 4)
            let context = try #require(CGContext(
                data: &buffer,
                width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            bytes = buffer
        }

        func alpha(_ x: Int, _ y: Int) -> Double {
            Double(bytes[(y * size + x) * 4 + 3]) / 255
        }

        /// How many pixels of a row carry ink.
        func width(atRow y: Int) -> Int {
            (0 ..< size).count { alpha($0, y) > 0.5 }
        }

        /// Pixels that are neither ink nor empty: the length of the soft edge.
        var softPixels: Int {
            var count = 0
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let a = alpha(x, y)
                    if a > 0.1, a < 0.9 { count += 1 }
                }
            }
            return count
        }
    }

    /// Drawn at 512 like `disc` and `hoop`, and for the same reason plus one
    /// more: the diagonals. A straight edge survives magnification and a slant
    /// does not — at 64 a hazard stripe stair-steps the moment it is drawn
    /// 300px tall.
    @Test("the flat shapes are drawn at 512", arguments: names)
    func drawnLarge(name: String) throws {
        #expect(try Picture(name: name).size == 512)
    }

    /// A shape is judged by where it stops. These are hard by design — the
    /// Flat family is paint, and a soft edge is a light — so what is checked is
    /// the width of the edge, not a fade. Only the antialiasing texel or two on
    /// a diagonal is allowed to be neither ink nor empty.
    @Test("the flat shapes have hard edges", arguments: names)
    func hardEdges(name: String) throws {
        let picture = try Picture(name: name)
        let total = picture.size * picture.size
        #expect(
            Double(picture.softPixels) < Double(total) * 0.015,
            "\(name) has \(picture.softPixels) soft pixels",
        )
    }

    @Test("every flat shape leaves a margin for its antialiasing", arguments: names)
    func keepsAMargin(name: String) throws {
        let picture = try Picture(name: name)
        for i in 0 ..< picture.size {
            #expect(picture.alpha(i, 0) < 0.06, "\(name) is clipped at its top edge")
            #expect(picture.alpha(i, picture.size - 1) < 0.06, "\(name) is clipped at its bottom edge")
            #expect(picture.alpha(0, i) < 0.06, "\(name) is clipped at its left edge")
            #expect(picture.alpha(picture.size - 1, i) < 0.06, "\(name) is clipped at its right edge")
        }
    }

    /// Up is (0, −1), the axis the emitter aligns to a velocity. A chevron that
    /// pointed down would march backwards.
    @Test("the chevron points up")
    func chevronPointsUp() throws {
        let p = try Picture(name: "chevron")
        // Ink under the apex, none under the notch of the V.
        #expect(p.alpha(256, 100) > 0.9, "no ink under the tip")
        #expect(p.alpha(256, 400) < 0.05, "the notch is filled")
        // The arms end low and wide.
        #expect(p.alpha(20, 370) > 0.9, "the left arm does not reach its end")
        #expect(p.alpha(491, 370) > 0.9, "the right arm does not reach its end")
        // And nothing above the arms, out at the sides.
        #expect(p.alpha(20, 60) < 0.05)
    }

    @Test("the arrow points up, with a shaft below its head")
    func arrowPointsUp() throws {
        let p = try Picture(name: "arrow")
        #expect(p.alpha(256, 30) > 0.9, "no tip")
        #expect(p.alpha(60, 30) < 0.05, "the head is not pointed")
        // Just above the base of the head: nearly full width. Just below: shaft.
        #expect(p.width(atRow: 240) > 400)
        #expect(p.width(atRow: 300) < 200)
        #expect(p.alpha(256, 480) > 0.9, "no shaft")
        #expect(p.alpha(30, 480) < 0.05)
    }

    @Test("the triangle is solid, pointed at the top and wide at the base")
    func triangleIsSolid() throws {
        let p = try Picture(name: "triangle")
        #expect(p.alpha(256, 256) > 0.9)
        #expect(p.alpha(20, 20) < 0.05)
        // Narrow near the top, wide near the bottom.
        let top = p.width(atRow: 140)
        let base = p.width(atRow: 340)
        #expect(base > top * 2, "top \(top), base \(base)")
    }

    /// Slanted, not upright: what makes it a hazard stripe rather than a bar.
    @Test("the stripe leans")
    func stripeLeans() throws {
        let p = try Picture(name: "stripe")
        #expect(p.alpha(100, 490) > 0.9, "no ink at the bottom left")
        #expect(p.alpha(400, 490) < 0.05, "the bottom right is filled")
        #expect(p.alpha(400, 20) > 0.9, "no ink at the top right")
        #expect(p.alpha(100, 20) < 0.05, "the top left is filled")
        #expect(p.alpha(256, 256) > 0.9)
    }

    /// The vector anchor handle: an outline, hollow in the middle.
    @Test("the node is a hollow square")
    func nodeIsHollow() throws {
        let p = try Picture(name: "node")
        #expect(p.alpha(256, 256) < 0.05, "the middle is filled")
        #expect(p.alpha(256, 30) > 0.9, "no top edge")
        #expect(p.alpha(256, 481) > 0.9, "no bottom edge")
        #expect(p.alpha(30, 256) > 0.9, "no left edge")
        #expect(p.alpha(481, 256) > 0.9, "no right edge")
        #expect(p.alpha(20, 20) > 0.9, "the corner is missing")
    }

    @Test("the cross is a plus, empty in its corners")
    func crossIsAPlus() throws {
        let p = try Picture(name: "cross")
        for (x, y) in [(40, 40), (471, 40), (40, 471), (471, 471)] {
            #expect(p.alpha(x, y) < 0.05, "corner (\(x), \(y)) is inked")
        }
        #expect(p.alpha(256, 256) > 0.9)
        #expect(p.alpha(256, 20) > 0.9, "the top arm is short")
        #expect(p.alpha(20, 256) > 0.9, "the left arm is short")
    }

    /// Core names them and the renderer draws them, from two separate lists.
    @Test("core and the renderer agree on which shapes are flat")
    func listsAgree() {
        #expect(
            Set(BuiltInSprite.flatShapes)
                == Set(BuiltInTextures.Shape.flat.map(\.path)),
        )
        #expect(BuiltInSprite.flatShapes.count == Self.names.count)
        for path in BuiltInSprite.flatShapes {
            #expect(BuiltInSprite.isKnown(path))
        }
    }
}
