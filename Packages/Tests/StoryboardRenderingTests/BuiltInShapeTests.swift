import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import StoryboardRendering

/// The shapes the app draws for itself.
///
/// A hard edge is invisible in the code and unmistakable on screen: the streak
/// shipped as a solid bar with square sides, and stretched by a preset it read
/// as a plank of wood rather than as a trail of light. These check the edges,
/// which is the property that separates a particle from a rectangle.
@Suite("Built-in shapes")
struct BuiltInShapeTests {
    private func pixels(_ shape: BuiltInTextures.Shape) throws -> (
        alpha: (Int, Int) -> Double, size: Int
    ) {
        let data = try #require(BuiltInTextures.data(for: shape.path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let size = image.width
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let context = try #require(CGContext(
            data: &bytes,
            width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        let copy = bytes
        return ({ x, y in Double(copy[(y * size + x) * 4 + 3]) / 255 }, size)
    }

    /// Every shape but the square fades out before its own edge. A particle
    /// that reaches its bounds draws its bounding box, and a hundred of those
    /// overlapping is a pile of rectangles.
    /// `square` and `fill` are exempt, and honest about it: one is a hard shape
    /// by name, the other exists precisely to reach its own edges — a bar drawn
    /// with a margin is a bar that comes out narrower than it was asked for,
    /// with blurred ends.
    @Test(
        "a shape fades out before its edge",
        // `disc` and `hoop` join them: a drawn shape is measured by where it
        // stops, so it has to reach the size it was asked for.
        arguments: BuiltInTextures.Shape.allCases.filter {
            $0 != .square && $0 != .fill && $0 != .disc && $0 != .hoop
        },
    )
    func shapesFadeAtTheirEdge(shape: BuiltInTextures.Shape) throws {
        let (alpha, size) = try pixels(shape)

        for i in 0 ..< size {
            #expect(alpha(i, 0) < 0.06, "\(shape) touches its top edge at \(i)")
            #expect(alpha(i, size - 1) < 0.06, "\(shape) touches its bottom edge at \(i)")
            #expect(alpha(0, i) < 0.06, "\(shape) touches its left edge at \(i)")
            #expect(alpha(size - 1, i) < 0.06, "\(shape) touches its right edge at \(i)")
        }
    }

    /// The failure this suite was written for.
    ///
    /// A streak is a spindle: it has to soften **sideways** as well as
    /// lengthways. Clipping a strip and filling it gives a bar whose long sides
    /// are a hard cut, which is what shipped — and a preset that stretched it
    /// turned the whole screen into planks.
    @Test("the streak has soft sides, not just soft ends")
    func streakIsASpindle() throws {
        let (alpha, size) = try pixels(.streak)
        let middle = size / 2

        // Bright down the centre.
        #expect(alpha(middle, middle) > 0.6)

        // Walking outward from the centre, the fall to nothing is gradual.
        // A clipped strip drops from full to zero between two pixels.
        var previous = alpha(middle, middle)
        var biggestDrop = 0.0
        for x in middle ..< size {
            let value = alpha(x, middle)
            biggestDrop = max(biggestDrop, previous - value)
            previous = value
        }

        #expect(biggestDrop < 0.3, "the streak's side falls off in one step: \(biggestDrop)")
    }

    /// A streak tapers along its length too, or it is a bar with soft sides.
    @Test("the streak tapers to a point at both ends")
    func streakTapers() throws {
        let (alpha, size) = try pixels(.streak)
        let middle = size / 2

        func width(atRow y: Int) -> Int {
            (0 ..< size).count { alpha($0, y) > 0.1 }
        }

        let waist = width(atRow: middle)
        #expect(waist > 2, "the streak has no body")
        #expect(width(atRow: size / 8) < waist)
        #expect(width(atRow: size - size / 8) < waist)
    }

    /// The fill reaches its own edges, which is the whole reason it exists.
    ///
    /// `square` insets its ink by 18% so a spinning particle keeps its corners.
    /// Stretched into a bar that margin stretches too: the ends come out
    /// blurred and the bar measures a third narrower than it was asked for —
    /// a shape is judged by its size, so every transparent pixel is a pixel of
    /// the bar somebody wanted.
    @Test("the fill covers its whole canvas")
    func fillReachesTheEdges() throws {
        let (alpha, size) = try pixels(.fill)

        // Opaque in all four corners, which is what "no margin" means.
        for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
            #expect(alpha(x, y) > 0.95, "the fill is transparent at (\(x), \(y))")
        }
    }
}
