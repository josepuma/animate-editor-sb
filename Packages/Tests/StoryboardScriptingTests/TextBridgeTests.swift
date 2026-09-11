import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// `text()` — one builder per character.
///
/// The guards are about what the bridge *promises*, not that it produced
/// sprites: a line that draws is a line that draws whether or not it is laid
/// out, coloured or measured correctly, and this project has already shipped a
/// table of easing names spelled backwards behind a test asserting exactly
/// that much.
@Suite("Text bridge", .serialized)
struct TextBridgeTests {
    private func run(_ source: String, duration: Double = 1000) -> ScriptRuntime.Outcome {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: duration, seed: 1,
        ))
    }

    @Test("one sprite per visible character")
    func oneSpritePerGlyph() {
        let outcome = run("text('ABC').forEach(g => g.fade(0, 10, 0, 1))")

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(outcome.sprites.count == 3)
    }

    /// A space has an advance and no ink, so a sprite for it draws nothing —
    /// and every one of them still costs a line in the exported file.
    @Test("whitespace advances without drawing")
    func whitespaceDrawsNothing() {
        let spaced = run("text('A B').forEach(g => g.fade(0, 10, 0, 1))")
        #expect(spaced.sprites.count == 2)

        // But it still takes room: the two glyphs must sit further apart than
        // they would with no gap between them.
        let tight = run("text('AB').forEach(g => g.fade(0, 10, 0, 1))")
        let gap = { (o: ScriptRuntime.Outcome) in
            abs(o.sprites[1].defaultX - o.sprites[0].defaultX)
        }
        #expect(gap(spaced) > gap(tight))
    }

    /// Each glyph gets its own sprite so each can take its own rule — which is
    /// the entire reason this exists rather than one sprite holding a word.
    @Test("every glyph can be animated on its own")
    func glyphsAnimateIndependently() {
        let outcome = run("""
            text('ABCD').forEach((g, i) => {
                g.fade(0, 10, 0, 1)
                g.move(i * 100, i * 100 + 500, 0, 0, 100, 100)
            })
            """)

        let starts = outcome.sprites.compactMap { sprite in
            sprite.commands.first { if case .move = $0.payload { true } else { false } }?.startTime
        }
        #expect(Set(starts).count == 4, "all four glyphs share a start time")
    }

    /// Laid out around the centre, because a clip's transform rotates about
    /// that point: a line placed from one corner sweeps one end through an arc.
    @Test("the line is centred on its anchor")
    func lineIsCentred() {
        let outcome = run("text('ABCDE', { x: 400, y: 100 }).forEach(g => g.fade(0, 10, 0, 1))")

        let xs = outcome.sprites.map(\.defaultX)
        let centre = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        #expect(abs(centre - 400) < 1, "centred at \(centre), not 400")
        #expect(outcome.sprites.allSatisfy { $0.defaultY == 100 })
    }

    /// Ordered left to right, and spaced: two glyphs landing on the same point
    /// is a line nobody can read.
    @Test("glyphs are laid out in reading order")
    func readingOrder() {
        let outcome = run("text('ABCD').forEach(g => g.fade(0, 10, 0, 1))")
        let xs = outcome.sprites.map(\.defaultX)

        #expect(xs == xs.sorted())
        #expect(Set(xs).count == xs.count)
    }

    /// `tracking` opens the line up. Without a guard the parameter could be
    /// read and discarded and nothing would say so.
    @Test("tracking widens the line")
    func trackingWidens() {
        let width = { (source: String) -> Double in
            let xs = self.run(source).sprites.map(\.defaultX)
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }
        let tight = width("text('ABCD').forEach(g => g.fade(0, 10, 0, 1))")
        let loose = width("text('ABCD', { tracking: 20 }).forEach(g => g.fade(0, 10, 0, 1))")

        #expect(loose > tight + 50, "tight \(tight), loose \(loose)")
    }

    /// Size has to reach the layout, not only the texture: glyphs drawn twice
    /// as large that sit at the same spacing overlap.
    @Test("size changes the spacing")
    func sizeChangesSpacing() {
        let width = { (source: String) -> Double in
            let xs = self.run(source).sprites.map(\.defaultX)
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }
        let small = width("text('ABCD', { size: 20 }).forEach(g => g.fade(0, 10, 0, 1))")
        let large = width("text('ABCD', { size: 80 }).forEach(g => g.fade(0, 10, 0, 1))")

        #expect(large > small * 2, "small \(small), large \(large)")
    }

    /// Every glyph points at a `__text__/` path, which is how the renderer
    /// knows to draw a character rather than look for a file.
    @Test("glyphs name synthetic text paths")
    func glyphPaths() {
        let outcome = run("text('AB').forEach(g => g.fade(0, 10, 0, 1))")
        #expect(outcome.sprites.allSatisfy { TextSprite.isText($0.filePath) })
    }

    /// The same character in the same style is one texture, however many
    /// sprites name it — a repeated letter must not mint an atlas entry each.
    @Test("a repeated character resolves to one path")
    func repeatedCharacterSharesPath() {
        let outcome = run("text('AA').forEach(g => g.fade(0, 10, 0, 1))")
        #expect(Set(outcome.sprites.map(\.filePath)).count == 1)
        #expect(outcome.sprites.count == 2)
    }

    /// Different characters must not collide onto one path, which would draw
    /// the whole line as the same letter.
    @Test("different characters take different paths")
    func differentCharactersDiffer() {
        let outcome = run("text('ABCD').forEach(g => g.fade(0, 10, 0, 1))")
        #expect(Set(outcome.sprites.map(\.filePath)).count == 4)
    }

    /// A builder reports what it drew, so a script can stack or space around
    /// the real glyph rather than guessing from the point size — which is never
    /// the width of a character.
    @Test("a glyph reports its own size and place")
    func glyphReportsItself() {
        let outcome = run("""
            const g = text('A')[0]
            g.fade(0, 10, 0, 1)
            if (!(g.width > 0 && g.height > 0)) { throw new Error('no size') }
            if (g.character !== 'A') { throw new Error('wrong character: ' + g.character) }
            if (!(g.x > 0)) { throw new Error('no x') }
            """)
        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// An option written wrong is an error, not a default.
    ///
    /// A name that does not exist arrives as `undefined`; treating that the
    /// same as an absent option is how `Ease.outQuad` once animated as linear
    /// in a saved project, with nothing to say so.
    /// The option has to be one **only this bridge reads**.
    ///
    /// The first version of this test used `origin`, which the sprite builder
    /// also reads — so it passed while the text bridge's own guard was deleted,
    /// measuring somebody else's check. Caught by mutation: with the guard
    /// removed, `tracking: <a name that does not exist>` drew two sprites and
    /// reported nothing.
    @Test("a misspelled option is refused", arguments: ["tracking", "size", "x", "font"])
    func misspelledOptionIsRefused(option: String) {
        let outcome = run("text('AB', { \(option): Origin.middleLeft }).forEach(g => g.fade(0, 10, 0, 1))")
        #expect(!outcome.diagnostics.isEmpty, "'\(option)' written wrong was accepted")
        #expect(outcome.sprites.isEmpty)
    }

    /// An option nobody wrote is fine, which is the other half of that rule.
    @Test("an absent option is fine")
    func absentOptionIsFine() {
        let outcome = run("text('AB', { size: 60 }).forEach(g => g.fade(0, 10, 0, 1))")
        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(outcome.sprites.count == 2)
    }

    /// A script must not be able to crash the editor it runs in. `0/0` reaches
    /// Swift as NaN, and `Int(nan)` is not an error — it is a **trap**.
    @Test("a non-finite option does not crash")
    func nonFiniteOptionSurvives() {
        let outcome = run("text('AB', { size: 0/0, x: 0/0 }).forEach(g => g.fade(0, 10, 0, 1))")
        #expect(outcome.sprites.count == 2)
        #expect(outcome.sprites.allSatisfy { $0.defaultX.isFinite && $0.defaultY.isFinite })
    }

    /// An empty string is a line with nothing in it, not a failure.
    @Test("an empty string draws nothing and does not fail")
    func emptyString() {
        let outcome = run("text('').forEach(g => g.fade(0, 10, 0, 1))")
        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(outcome.sprites.isEmpty)
    }

    /// Glyphs are ordinary sprites, so the sprite ceiling has to hold here too:
    /// a script asking for a novel must truncate rather than run for a minute
    /// building sprites nobody will see.
    @Test("the sprite ceiling holds for text")
    func ceilingHolds() {
        let outcome = run("""
            for (let i = 0; i < 400; i += 1) {
                text('ABCDEFGHIJ').forEach(g => g.fade(0, 10, 0, 1))
            }
            """)
        #expect(outcome.sprites.count <= ScriptLimits.maximumSprites)
    }
}
