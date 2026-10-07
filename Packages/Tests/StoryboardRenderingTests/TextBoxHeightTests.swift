import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// Core predicts how tall a glyph's texture is; the renderer draws it.
///
/// Pivot Bottom anchors a character on the bottom edge of that texture, and
/// Core cannot open the PNG to find out where that edge is. So both sides read
/// one padding from `TextSprite`, and this suite draws real glyphs to hold the
/// prediction to the pixels. Core Text only, no `MTLDevice`: it runs in CI.
///
/// The metrics come from `TextTextures.metrics` directly rather than through
/// `TextMetrics.measure`: installing the global here would change every width
/// the Core suites lay out against.
@Suite("Text box height")
struct TextBoxHeightTests {
    private static let styles: [TextStyle] = [
        TextStyle(),
        TextStyle(font: "Helvetica", size: 30, isBold: true, strokeWidth: 5),
        TextStyle(font: "Helvetica", size: 96, isItalic: true),
        TextStyle(font: "Hiragino Sans", size: 61, strokeWidth: 1.5),
    ]

    private func textureHeight(_ character: Character, style: TextStyle) throws -> Int {
        TextTextures.register(character, style: style)
        let data = try #require(TextTextures.data(for: TextSprite.rawPath(for: character, style: style)))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return image.height
    }

    @Test("the predicted box is the drawn texture's height", arguments: styles)
    func boxMatchesTexture(style: TextStyle) throws {
        for character in ["A", "g", "あ", "."] as [Character] {
            let glyph = TextTextures.metrics(character, style: style)
            let drawn = try textureHeight(character, style: style)
            #expect(
                TextSprite.boxHeight(glyph, style: style) == Double(drawn),
                "\(character) · \(style)",
            )
        }
    }

    /// The padding grows with the stroke; with a thin stroke it has a floor.
    @Test("padding has a floor and follows the stroke")
    func padding() {
        #expect(TextSprite.padding(for: TextStyle()) == 4)
        #expect(TextSprite.padding(for: TextStyle(strokeWidth: 1)) == 4)
        #expect(TextSprite.padding(for: TextStyle(strokeWidth: 5)) == 10)
    }
}
