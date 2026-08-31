import CoreGraphics
import Metal
import MetalKit
import Testing

@testable import StoryboardRendering

@Suite("Oversized textures")
struct TextureDownscaleTests {
    /// A solid image of a given size, encoded as PNG.
    private func png(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil,
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func load(width: Int, height: Int) throws -> LoadedTexture? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let data = png(width: width, height: height)
        else { return nil }
        return try MTKTextureLoader.Source.data(data)
            .load(with: MTKTextureLoader(device: device))
    }

    /// A background far larger than the stage would otherwise claim most of an
    /// atlas page on its own, and be refused at playback besides.
    @Test("an oversized image is shrunk to the format's limit")
    func oversizedIsShrunk() throws {
        guard let loaded = try load(width: 3506, height: 2329) else { return }

        #expect(max(loaded.texture.width, loaded.texture.height) == OsuCanvas.maximumTextureSize)
        // Aspect preserved, so nothing stretches.
        let ratio = Double(loaded.texture.width) / Double(loaded.texture.height)
        #expect(abs(ratio - 3506.0 / 2329.0) < 0.01)
    }

    /// The point of keeping the two sizes apart: shrinking the texture must not
    /// shrink the sprite. Reading the size from the texture would draw a
    /// downscaled background at a fraction of its intended size.
    @Test("shrinking a texture does not shrink the sprite")
    func drawnSizeSurvivesTheShrink() throws {
        guard let loaded = try load(width: 3506, height: 2329) else { return }

        #expect(loaded.drawnSize.x == 3506)
        #expect(loaded.drawnSize.y == 2329)
        #expect(Float(loaded.texture.width) < loaded.drawnSize.x)
    }

    @Test("an image within the limit is left alone")
    func smallImagesAreUntouched() throws {
        guard let loaded = try load(width: 512, height: 256) else { return }

        #expect(loaded.texture.width == 512)
        #expect(loaded.texture.height == 256)
        #expect(loaded.drawnSize == SIMD2<Float>(512, 256))
    }
}
