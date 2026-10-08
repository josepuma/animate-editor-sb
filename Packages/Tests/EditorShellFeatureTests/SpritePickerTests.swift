import CoreGraphics
import Foundation
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// The sprite picker's naming, and the thumbnails it is fed.
@Suite("Sprite picker")
@MainActor
struct SpritePickerTests {
    /// What the field says for a stored path. A path the catalogue does not
    /// know is a beatmap's own image, "Custom" — never the nearest built-in,
    /// which would claim the sprite is something it is not.
    @Test("the field names the dot, built-ins and custom paths")
    func titles() {
        #expect(SpritePicker.title(for: "") == "Adjustable Dot")
        #expect(SpritePicker.title(for: BuiltInSprite.hudArcs) == "HUD Arcs")
        #expect(SpritePicker.title(for: "sb/my-own.png") == "Custom")
    }

    private func image() -> CGImage {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )!
        return context.makeImage()!
    }

    /// A tile scrolled back into view must not decode again: each path is
    /// made once, and lands in the model for every tile that shows it.
    @Test("a thumbnail is made once and lands in the model")
    func thumbnailsAreMadeOnce() async throws {
        let shell = EditorShellModel()
        let made = Counter()
        let picture = image()
        shell.spriteThumbnail = { _ in made.increment(); return picture }

        shell.requestSpriteThumbnail(BuiltInSprite.glow)
        shell.requestSpriteThumbnail(BuiltInSprite.glow)
        shell.spriteThumbnailSource.request(BuiltInSprite.glow)

        for _ in 0 ..< 200 where shell.spriteThumbnails[BuiltInSprite.glow] == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(shell.spriteThumbnails[BuiltInSprite.glow] != nil)
        #expect(made.value == 1)
        #expect(shell.spriteThumbnailSource.image(BuiltInSprite.glow) != nil)
    }
}

/// A thread-safe count, for a closure called off the main thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
