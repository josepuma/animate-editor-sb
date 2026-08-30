import CoreGraphics
import ImageIO
import StoryboardCore
import Testing
import UniformTypeIdentifiers

@testable import StoryboardRendering

/// Making the image a derived path names.
@Suite("Derived textures")
struct DerivedTextureTests {
    /// A hard-edged white square, so a blur has something obvious to soften.
    private func square(size: Int = 32) -> Data {
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func dimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (image.width, image.height)
    }

    @Test("a plain path produces nothing")
    func plainPathsAreNotDerived() {
        #expect(DerivedTextures.data(for: "sb/a.png") { _ in self.square() } == nil)
    }

    /// A blur pushes light past the edges of its source. On a canvas the same
    /// size, that light is cut off and the result is a soft image with hard
    /// sides — a rectangle rather than a glow.
    @Test("a blurred image is padded to hold its own spread")
    func blurGrowsTheCanvas() throws {
        DerivedTextures.clearCache()
        let path = DerivedSprite.blurred("sb/a.png", radius: 8)

        let blurred = try #require(DerivedTextures.data(for: path) { _ in self.square(size: 32) })
        let size = try #require(dimensions(of: blurred))

        #expect(size.width > 32)
        #expect(size.height > 32)
    }

    @Test("a missing source produces nothing rather than failing")
    func missingSource() {
        DerivedTextures.clearCache()
        let path = DerivedSprite.blurred("sb/gone.png", radius: 8)

        #expect(DerivedTextures.data(for: path) { _ in nil } == nil)
    }

    /// Blurring is expensive and a texture is asked for once per sprite —
    /// hundreds of times for one emitter.
    @Test("repeated requests reuse the same image")
    func cached() throws {
        DerivedTextures.clearCache()
        let path = DerivedSprite.blurred("sb/a.png", radius: 6)

        let first = try #require(DerivedTextures.data(for: path) { _ in self.square() })
        // A source that would fail: the second call must not reach it.
        let second = try #require(DerivedTextures.data(for: path) { _ in nil })

        #expect(first == second)
    }
}
