import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// Glyphs drawn for a vertical line, in the font's vertical forms.
///
/// Core Text only, no GPU: these run on CI. Measured with `metrics`, which
/// installs nothing — `TextSnapshotTests` needs the global measurer nil.
@Suite("Vertical glyphs")
struct VerticalGlyphTests {
    private let vertical = TextStyle(font: "Hiragino Sans", size: 48, isVertical: true)
    private let horizontal = TextStyle(font: "Hiragino Sans", size: 48)

    private struct Ink {
        let width: Int
        let height: Int
        let inkWidth: Int
        let inkHeight: Int

        init(_ data: Data) throws {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var minX = width, maxX = -1, minY = height, maxY = -1
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 128 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            inkWidth = max(0, maxX - minX + 1)
            inkHeight = max(0, maxY - minY + 1)
        }
    }

    private func drawn(_ character: Character, _ style: TextStyle, scale: Int = 1) throws -> Ink {
        TextTextures.register(character, style: style)
        let path = TextSprite.path(for: character, style: style)
        return try Ink(#require(scale > 1 ? TextTextures.data(for: path, scale: scale) : TextTextures.data(for: path)))
    }

    @Test("a vertical box is as wide as the line and as tall as its advance")
    func metrics() {
        let kana = TextTextures.metrics("あ", style: vertical)
        #expect(abs(kana.height - 48) < 0.5, "one em down the column")
        #expect(kana.width > 40, "across: the line's ascent and descent")
    }

    @Test("the texture is that box and its padding, exactly")
    func textureSize() throws {
        let ink = try drawn("あ", vertical)
        let box = TextTextures.metrics("あ", style: vertical)
        let padding = TextSprite.padding(for: vertical)
        #expect(ink.width == Int((box.width + padding * 2).rounded(.up)))
        #expect(ink.height == Int(TextSprite.boxHeight(box, style: vertical)))
    }

    /// The point of vertical forms: the long vowel mark stands up.
    @Test("ー stands in a column and lies in a line")
    func longVowel() throws {
        let column = try drawn("ー", vertical)
        let line = try drawn("ー", horizontal)
        #expect(column.inkHeight > column.inkWidth * 3)
        #expect(line.inkWidth > line.inkHeight * 3)
    }

    /// What tells vertical forms from turning the whole glyph: the kanji
    /// for "one" is a bar exactly like ー, but a kanji stands upright in a
    /// column — so it stays flat while ー stands. Turned wholesale, both would
    /// stand, and the test above could not tell.
    @Test("一 stays flat in a column while ー stands")
    func kanjiStaysUpright() throws {
        let one = try drawn("一", vertical)
        #expect(one.inkWidth > one.inkHeight * 3)
    }

    @Test("Latin lies on its side in a column")
    func latinOnItsSide() throws {
        let column = try drawn("l", vertical)
        let line = try drawn("l", horizontal)
        #expect(line.inkHeight > line.inkWidth * 2)
        #expect(column.inkWidth > column.inkHeight * 2)
    }

    @Test("drawn larger for Ink and Outline, it is the same box three times over")
    func scaled() throws {
        let one = try drawn("愛", vertical)
        let three = try drawn("愛", vertical, scale: 3)
        #expect(three.width == one.width * 3 && three.height == one.height * 3)
    }
}
