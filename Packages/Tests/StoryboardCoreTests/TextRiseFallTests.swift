import Foundation
import Testing

@testable import StoryboardCore

/// Rise and Fall leave with `_M` from wherever the glyph is.
///
/// Written as `_MY`, they overrode the `_M` entrance outright — the resolver,
/// like osu!, lets an axis command win over the pair and holds its start before
/// its first command — so a glyph that rose in sat still at its rest height and
/// popped in place, and one carrying Travel Y snapped back as it left. Read from
/// resolved states, which is what a viewer sees.
@Suite("Text Rise/Fall exit")
struct TextRiseFallTests {
    private typealias P = TextEffect.Param

    private func sprites(_ values: [String: EffectValue], duration: Double = 3000) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: duration)
        node.values = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        node.seed = 8371
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    private func state(_ sprite: StoryboardSprite, at time: Double) throws -> SpriteRenderState {
        let states = StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time)
        return try #require(states.first)
    }

    /// The first line drops from 160px above; halfway down it is somewhere
    /// between, not already standing on the line.
    @Test("title-drop is still falling halfway through its drop")
    func titleDropFalls() throws {
        let preset = try #require(TextEffect.presets.first { $0.id == "title-drop" })
        let drawn = sprites(preset.values.merging([P.text: .text("AB\nCD")]) { _, new in new }, duration: preset.duration)
        let first = try #require(drawn.first)
        let midway = try state(first, at: 150)
        #expect(midway.y < first.defaultY - 1, "still above where it lands")
        #expect(midway.y >= first.defaultY - 160 - 1e-9)
    }

    @Test("a vertical entrance shows under a Rise or Fall exit", arguments: ["Rise", "Fall"])
    func entranceIsVisible(exit: String) throws {
        let drawn = sprites([
            P.text: .text("ab"), P.fadeIn: .number(600), P.fadeOut: .number(400),
            P.riseFrom: .number(80), P.exit: .choice(exit),
        ])
        let first = try #require(drawn.first)
        let midway = try state(first, at: 300)
        #expect(midway.y > first.defaultY + 5, "rising in from 80px below")
    }

    /// The exit starts where the travel left the glyph, on both axes.
    @Test("a Rise or Fall exit after Travel does not jump", arguments: ["Rise", "Fall"])
    func noJumpAfterTravel(exit: String) throws {
        let drawn = sprites([
            P.text: .text("ab"), P.fadeIn: .number(300), P.fadeOut: .number(400),
            P.driftX: .number(40), P.driftY: .number(60), P.exit: .choice(exit),
        ])
        let first = try #require(drawn.first)
        let exitStart = 3000.0 - 400
        let before = try state(first, at: exitStart - 1)
        let after = try state(first, at: exitStart + 1)
        #expect(abs(after.y - before.y) < 2)
        #expect(abs(after.x - before.x) < 2)
        let end = try state(first, at: 3000)
        let lift = exit == "Rise" ? -60.0 : 60
        #expect(abs(end.y - (first.defaultY + 60 + lift)) < 1e-6)
        #expect(abs(end.x - (first.defaultX + 40)) < 1e-6)
    }
}
