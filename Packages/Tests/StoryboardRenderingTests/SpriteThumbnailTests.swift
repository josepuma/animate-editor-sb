import CoreGraphics
import Foundation
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// The renderer's side of the picker: names from the catalogue, and a small
/// picture for every entry. Core Graphics only, so it runs on CI.
@Suite("Sprite thumbnails")
struct SpriteThumbnailTests {
    /// One list of names: the renderer reads the catalogue rather than
    /// keeping a copy that drifts.
    @Test("the renderer's names are the catalogue's")
    func titlesAgree() {
        for shape in BuiltInTextures.Shape.allCases where shape != .hoop {
            #expect(shape.title == BuiltInSprite.entry(for: shape.path)?.title, "\(shape)")
        }
        for texture in BuiltInTextures.Texture.allCases {
            #expect(texture.title == BuiltInSprite.entry(for: texture.path)?.title, "\(texture)")
        }
    }

    @Test("every catalogue entry has a small picture", arguments: BuiltInSprite.catalogue.map(\.path))
    func everyEntryHasAThumbnail(path: String) throws {
        let image = try #require(BuiltInTextures.thumbnail(for: path), "no thumbnail for \(path)")
        #expect(max(image.width, image.height) <= 128)
        #expect(max(image.width, image.height) >= 32)
    }

    @Test("a path that is not a built-in has no picture")
    func unknownHasNone() {
        #expect(BuiltInTextures.thumbnail(for: "sb/my-own.png") == nil)
    }
}
