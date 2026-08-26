import CoreGraphics
import ImageIO
import Metal
import MetalKit
import Testing
import UniformTypeIdentifiers

@testable import StoryboardRendering

/// The atlas assembles pages with a blit, which copies bytes without
/// reordering channels. Every decoded sprite must therefore land as
/// `.rgba8Unorm`, or warm colours come out blue.
@Suite("Texture decoding")
struct TextureDecodingTests {
    /// A 2×2 PNG with one fully saturated pixel per corner.
    private static func makeTestPNG() -> Data? {
        let width = 2
        let height = 2
        var pixels: [UInt8] = [
            255, 0, 0, 255, // top-left: red
            0, 255, 0, 255, // top-right: green
            0, 0, 255, 255, // bottom-left: blue
            255, 255, 255, 255, // bottom-right: white
        ]

        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue,
            )
        }), let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    @Test("decoded textures use the atlas pixel format")
    func decodesToRGBA() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        let png = try #require(Self.makeTestPNG())

        let loader = MTKTextureLoader(device: device)
        let texture = try MTKTextureLoader.Source.data(png).load(with: loader)

        #expect(texture.pixelFormat == .rgba8Unorm)
        #expect(texture.width == 2)
        #expect(texture.height == 2)
    }

    @Test("red stays red rather than turning blue")
    func preservesChannelOrder() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        let png = try #require(Self.makeTestPNG())

        let loader = MTKTextureLoader(device: device)
        let texture = try MTKTextureLoader.Source.data(png).load(with: loader)

        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: 2 * 4,
                from: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0,
            )
        }

        // Byte order is R, G, B, A. A BGRA source copied without conversion
        // would report (0, 0, 255) here — the bug this guards against.
        #expect(pixels[0] == 255, "red channel of the red pixel")
        #expect(pixels[1] == 0, "green channel of the red pixel")
        #expect(pixels[2] == 0, "blue channel of the red pixel")
        #expect(pixels[3] == 255, "alpha of the red pixel")

        // Top-right is green.
        #expect(pixels[4] == 0)
        #expect(pixels[5] == 255)
        #expect(pixels[6] == 0)

        // Bottom-left is blue.
        #expect(pixels[8] == 0)
        #expect(pixels[9] == 0)
        #expect(pixels[10] == 255)
    }

    @Test("decoding invalid data throws rather than crashing")
    func invalidDataThrows() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        let loader = MTKTextureLoader(device: device)
        let garbage = Data([0x00, 0x01, 0x02, 0x03])

        #expect(throws: RendererError.self) {
            try MTKTextureLoader.Source.data(garbage).load(with: loader)
        }
    }
}
