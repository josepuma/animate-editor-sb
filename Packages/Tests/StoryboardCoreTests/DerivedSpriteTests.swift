import Testing

@testable import StoryboardCore

/// Paths that name an image made from another one.
@Suite("Derived sprites")
struct DerivedSpriteTests {
    @Test("a blurred path round-trips")
    func roundTrip() {
        let path = DerivedSprite.blurred("sb/particle.png", radius: 12)
        let parsed = DerivedSprite.parse(path)

        #expect(parsed?.source == "sb/particle.png")
        #expect(parsed?.kind == .blur(radius: 12))
    }

    /// Sources have slashes of their own, so the parser cannot simply split on
    /// the first one it finds — it has to take the descriptor and keep the rest.
    @Test("a nested source path survives")
    func nestedSource() {
        let path = DerivedSprite.blurred("sb/effects/glow/dot.png", radius: 8)

        #expect(DerivedSprite.parse(path)?.source == "sb/effects/glow/dot.png")
    }

    @Test("an ordinary path is not derived")
    func plainPaths() {
        #expect(DerivedSprite.parse("sb/particle.png") == nil)
        #expect(!DerivedSprite.isDerived("sb/particle.png"))
        #expect(DerivedSprite.isDerived(DerivedSprite.blurred("a.png", radius: 4)))
    }

    @Test("a malformed derived path is refused rather than guessed at")
    func malformedPaths() {
        #expect(DerivedSprite.parse("__derived__/") == nil)
        #expect(DerivedSprite.parse("__derived__/blur8/") == nil)
        #expect(DerivedSprite.parse("__derived__/sharpen4/a.png") == nil)
    }

    /// A continuous slider would otherwise mint a texture for every position it
    /// passes through, and an atlas is a fixed size.
    @Test("nearby radii share one texture")
    func radiiAreQuantised() {
        let a = DerivedSprite.blurred("a.png", radius: 11.4)
        let b = DerivedSprite.blurred("a.png", radius: 12.3)
        let c = DerivedSprite.blurred("a.png", radius: 20)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("quantisation rounds to even steps")
    func quantisation() {
        #expect(DerivedSprite.quantise(0) == 0)
        #expect(DerivedSprite.quantise(0.9) == 0)
        #expect(DerivedSprite.quantise(1.1) == 2)
        #expect(DerivedSprite.quantise(15) == 16)
        #expect(DerivedSprite.quantise(-5) == 0)
    }

    /// Two sprites blurred by the same amount are the same image; two different
    /// sprites are not.
    @Test("the path identifies both the source and the blur")
    func pathsAreDistinct() {
        #expect(
            DerivedSprite.blurred("a.png", radius: 8)
                == DerivedSprite.blurred("a.png", radius: 8),
        )
        #expect(
            DerivedSprite.blurred("a.png", radius: 8)
                != DerivedSprite.blurred("b.png", radius: 8),
        )
    }
}
