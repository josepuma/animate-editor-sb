import CoreGraphics
import ImageIO
import Metal
import MetalKit
import StoryboardCore
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
        let texture = try MTKTextureLoader.Source.data(png).load(with: loader).texture

        // Compared against the atlas rather than against a literal: pages are
        // assembled with a blit, which copies bytes and requires both sides to
        // agree on what they mean. A test naming the format itself passes while
        // the two drift apart.
        #expect(texture.pixelFormat == TextureAtlas.pixelFormat)
        #expect(texture.width == 2)
        #expect(texture.height == 2)
    }

    @Test("red stays red rather than turning blue")
    func preservesChannelOrder() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        let png = try #require(Self.makeTestPNG())

        let loader = MTKTextureLoader(device: device)
        let texture = try MTKTextureLoader.Source.data(png).load(with: loader).texture

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

@Suite("Built-in textures")
struct BuiltInTextureTests {
    /// The two constants are spelled out separately because `StoryboardCore`
    /// sits below the renderer and cannot import it. A mismatch would leave a
    /// freshly dropped emitter asking the beatmap for a file that is not there,
    /// drawing nothing — which reads as the effect being broken.
    @Test("the emitter's default path is the one the renderer supplies")
    func emitterDefaultMatches() {
        #expect(EmitterEffect.defaultSpritePath == BuiltInTextures.particle)
    }

    @Test("the built-in particle decodes to an image")
    func particleDecodes() throws {
        let data = try #require(BuiltInTextures.data(for: BuiltInTextures.particle))
        #expect(!data.isEmpty)
        #expect(BuiltInTextures.isBuiltIn(BuiltInTextures.particle))
    }

    /// The two lists are written separately because `StoryboardCore` sits below
    /// the renderer and cannot import it. A preset naming a shape the renderer
    /// does not draw would render as flat quads — the effect looking broken
    /// rather than the asset looking missing.
    @Test("every built-in Core names is one the renderer supplies")
    func builtInListsAgree() {
        // The hoop is excluded on both sides: it is drawn on demand at a
        // given thickness, so it is a family of textures rather than one of the
        // fixed shapes.
        #expect(
            Set(BuiltInSprite.shapes)
                == Set(BuiltInTextures.Shape.allCases.filter { $0 != .hoop }.map(\.path)),
        )
        #expect(Set(BuiltInSprite.textures) == Set(BuiltInTextures.Texture.allCases.map(\.path)))
        #expect(Set(BuiltInSprite.all) == Set(BuiltInTextures.allPaths))
    }

    /// Core and the renderer have to spell a hoop's path the same way.
    ///
    /// The thickness is baked into the texture, so the path *is* the parameter
    /// — and the two sides build it independently because Core cannot see the
    /// renderer. A disagreement would leave the ring naming an image nothing
    /// provides: a bare quad, with nothing to say why.
    @Test("a hoop path round-trips between core and the renderer", arguments: [0.02, 0.12, 0.35, 0.5] as [Double])
    func hoopPathsAgree(thickness: Double) throws {
        let fromCore = BuiltInSprite.hoop(thickness: thickness)
        #expect(fromCore == BuiltInTextures.hoopPath(thickness: thickness))
        #expect(BuiltInTextures.data(for: fromCore) != nil, "no image for \(fromCore)")
    }

    /// A thicker ring really is thicker, rather than the same picture renamed.
    @Test("thickness changes the image")
    func thicknessDraws() throws {
        let thin = try #require(BuiltInTextures.data(for: BuiltInSprite.hoop(thickness: 0.02)))
        let thick = try #require(BuiltInTextures.data(for: BuiltInSprite.hoop(thickness: 0.4)))
        #expect(thin != thick)
    }

    /// The size `ShapeEffect` converts against has to be the size the renderer
    /// actually draws.
    ///
    /// Core cannot see the renderer, so it states the number itself — and a
    /// silent disagreement would make **every** shape come out at the wrong
    /// size with nothing to say why: a bar asked for at 854 would quietly be
    /// half or double that.
    @Test("the shape effect knows how large the built-in shapes are")
    func shapeSourceSizeMatches() throws {
        let data = try #require(BuiltInTextures.data(for: BuiltInSprite.square))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(Double(image.width) == ShapeEffect.sourceSize)
        #expect(Double(image.height) == ShapeEffect.sourceSize)
    }

    @Test("every shape decodes to an image", arguments: BuiltInTextures.Shape.allCases)
    func shapesDecode(shape: BuiltInTextures.Shape) throws {
        let data = try #require(BuiltInTextures.data(for: shape.path))
        #expect(!data.isEmpty)
    }

    /// A texture missing from the bundle would draw as a flat quad — the effect
    /// looking broken rather than the file looking absent.
    @Test("every shipped texture is in the bundle", arguments: BuiltInTextures.Texture.allCases)
    func texturesAreBundled(texture: BuiltInTextures.Texture) throws {
        let data = try #require(
            BuiltInTextures.data(for: texture.path),
            "\(texture.rawValue).png is not in the bundle",
        )
        #expect(data.count > 100)
        #expect(!texture.title.isEmpty)
    }

    /// Core spells out the stage's dimensions itself, because it sits below the
    /// renderer and cannot import `OsuCanvas`.
    ///
    /// A silent disagreement would snap clips to a centre that is not the
    /// centre, and draw the guide somewhere else again — the kind of wrongness
    /// that looks like a rendering bug rather than a constant.
    @Test("core and the renderer agree on the stage")
    func stageConstantsAgree() {
        #expect(StageSnap.Stage.width == Double(OsuCanvas.width))
        #expect(StageSnap.Stage.height == Double(OsuCanvas.height))
        #expect(StageSnap.Stage.minX == -Double(OsuCanvas.xOffset))
        #expect(StageSnap.Stage.maxX == Double(OsuCanvas.width) - Double(OsuCanvas.xOffset))
    }

    @Test("built-in paths are unique")
    func pathsAreUnique() {
        #expect(Set(BuiltInTextures.allPaths).count == BuiltInTextures.allPaths.count)
    }

    /// Projects saved before the shapes had names still ask for this.
    @Test("the original particle path still resolves")
    func legacyPathStillWorks() {
        #expect(BuiltInTextures.data(for: "__builtin__/particle.png") != nil)
    }

    @Test("a beatmap path is not treated as built in")
    func beatmapPathsPassThrough() {
        #expect(BuiltInTextures.data(for: "sb/particle.png") == nil)
        #expect(!BuiltInTextures.isBuiltIn("sb/particle.png"))
    }

    /// Requested once per sprite — thousands of times for a single emitter.
    @Test("repeated requests return the same data")
    func cached() {
        #expect(
            BuiltInTextures.data(for: BuiltInTextures.particle)
                == BuiltInTextures.data(for: BuiltInTextures.particle),
        )
    }
}
