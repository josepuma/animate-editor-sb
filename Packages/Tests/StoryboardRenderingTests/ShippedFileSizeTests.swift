import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// The sizes Core states for the shipped files, checked against the files.
///
/// Core Graphics only — no `MTLDevice` — so this runs on a hosted runner too.
@Suite("Shipped file sizes")
struct ShippedFileSizeTests {
    private func size(of path: String) throws -> (width: Double, height: Double) {
        let data = try #require(BuiltInTextures.data(for: path), "no image for \(path)")
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (Double(image.width), Double(image.height))
    }

    /// Core cannot open the files, so it declares the sizes of the ones that
    /// are not 512 square — and `Scale` multiplies whatever the file measures.
    /// A stale number would size every preset that uses that file wrong, with
    /// nothing in the inspector to say why.
    @Test("every declared size is the file's real size", arguments: Array(BuiltInSprite.fileSizes.keys))
    func declaredSizesMatch(path: String) throws {
        let declared = try #require(BuiltInSprite.fileSizes[path])
        let actual = try size(of: path)
        #expect(actual.width == declared.width && actual.height == declared.height,
                "\(path) is \(actual.width)×\(actual.height), Core says \(declared.width)×\(declared.height)")
    }

    /// The other half: a file that is not 512 square has to be declared, or
    /// the tests that size presets assume 512 for it and pass on wrong numbers.
    @Test("every file that is not 512 square is declared", arguments: BuiltInTextures.Texture.allCases)
    func undeclaredFilesAre512(texture: BuiltInTextures.Texture) throws {
        guard BuiltInSprite.fileSizes[texture.path] == nil else { return }
        let actual = try size(of: texture.path)
        #expect(actual.width == 512 && actual.height == 512,
                "\(texture.rawValue) is \(actual.width)×\(actual.height) and missing from fileSizes")
    }

    /// The folder is a loader detail: each texture has to be found in the one
    /// its `folder` names, and its saved path must not mention it.
    @Test("each texture loads from its folder and keeps a flat path", arguments: BuiltInTextures.Texture.allCases)
    func foldersAreInvisibleInPaths(texture: BuiltInTextures.Texture) throws {
        #expect(texture.path == "__builtin__/\(texture.rawValue).png")
        #expect(BuiltInTextures.data(for: texture.path) != nil,
                "\(texture.rawValue).png is not in Particles/\(texture.folder)")
    }

    /// Every shipped light shaft follows the built-in convention: white, with
    /// the shape in alpha. Anything else would fight `_C`.
    @Test("the sunshine textures are white with their shape in alpha",
          arguments: BuiltInTextures.Texture.allCases.filter { $0.folder == "Sunshine" })
    func sunshineIsWhite(texture: BuiltInTextures.Texture) throws {
        let data = try #require(BuiltInTextures.data(for: texture.path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width, height = image.height
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

        var peak = 0, transparent = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let a = Int(bytes[pixel + 3])
            peak = max(peak, a)
            if a == 0 { transparent += 1 }
            // Premultiplied: white means every channel equals alpha.
            for channel in 0..<3 {
                #expect(abs(Int(bytes[pixel + channel]) - a) <= 1, "\(texture.rawValue) is not white")
                if abs(Int(bytes[pixel + channel]) - a) > 1 { return }
            }
        }
        // A real mask has both: a bright shaft and empty space around it.
        #expect(peak > 200)
        #expect(transparent > width * height / 20)
    }
}
