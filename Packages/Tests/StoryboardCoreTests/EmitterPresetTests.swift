import Foundation
import Testing

@testable import StoryboardCore

/// A preset that produces nothing visible is worse than no preset: it reads as
/// a broken effect rather than as a starting point. Each one is checked for
/// output, not for looking right — that part is a judgement the tests cannot
/// make.
@Suite("Emitter presets")
struct EmitterPresetTests {
    private let evaluator = EffectEvaluator()

    /// Placed the way the app places it: at the preset's own length.
    private func node(_ preset: EffectPreset) -> EffectNode {
        EffectNode(
            id: preset.id,
            type: preset.effectType,
            name: preset.name,
            startTime: 0,
            duration: preset.duration,
            seed: 12,
            values: preset.values,
        )
    }

    @Test("every preset is complete and belongs to the emitter", arguments: EmitterEffect.presets)
    func presetsAreComplete(preset: EffectPreset) {
        #expect(preset.effectType == EmitterEffect.descriptor.type)
        #expect(!preset.name.isEmpty)
        #expect(!preset.summary.isEmpty)
        #expect(preset.duration >= 100)

        // Every declared parameter carries a value, so nothing falls back
        // silently. Position is not among them — it lives on the transform, so
        // it can be keyframed — but presets still carry x and y, which the
        // editor moves onto the transform when one is placed.
        let declared = Set(EmitterEffect.descriptor.parameters.map(\.id))
        #expect(declared.isSubset(of: Set(preset.values.keys)))
    }

    @Test("every preset produces sprites", arguments: EmitterEffect.presets)
    func presetsProduceSprites(preset: EffectPreset) {
        let sprites = evaluator.evaluate(node(preset))

        #expect(!sprites.isEmpty, "\(preset.id) produced nothing")
        #expect(sprites.allSatisfy { !$0.commands.isEmpty })
    }

    /// The check that matters: at some point during the effect there is
    /// something on screen with opacity to see.
    @Test("every preset is visible partway through", arguments: EmitterEffect.presets)
    func presetsAreVisible(preset: EffectPreset) {
        let placed = node(preset)
        let prepared = StoryboardResolver.prepare(evaluator.evaluate(placed))

        var anyVisible = false
        // A burst is over early in its block; a stream is thin at the start.
        // Sampling across the whole span covers both without a preset having to
        // declare when it is at its fullest.
        for fraction in [0.1, 0.3, 0.5, 0.8] {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: placed.duration * fraction, into: &states)
            if states.contains(where: { $0.visible && $0.opacity > 0.02 }) {
                anyVisible = true
                break
            }
        }

        #expect(anyVisible, "\(preset.id) is never visible")
    }

    /// Every preset draws a shape the renderer can actually supply.
    ///
    /// An **empty** path is one of those: it means the particle is built from
    /// its three shape numbers rather than named, which is what makes the form
    /// composable instead of a menu of nine textures. The check then moves to
    /// those numbers producing a path the renderer knows how to draw.
    @Test("every preset names a real sprite", arguments: EmitterEffect.presets)
    func presetsUseKnownSprites(preset: EffectPreset) {
        guard case let .text(path) = preset.values[EmitterEffect.Param.sprite] else {
            Issue.record("\(preset.id) has no sprite")
            return
        }
        guard !path.isEmpty else {
            func number(_ id: String) -> Double {
                if case let .number(value) = preset.values[id] { return value }
                return 0
            }
            let built = BuiltInSprite.particle(
                core: number(EmitterEffect.Param.core),
                edge: number(EmitterEffect.Param.edge),
                falloff: number(EmitterEffect.Param.softness),
            )
            #expect(
                BuiltInSprite.particleProfile(built) != nil,
                "\(preset.id) builds a particle the renderer cannot read back",
            )
            return
        }
        #expect(BuiltInSprite.all.contains(path), "\(preset.id) uses an unknown sprite: \(path)")
    }

    /// A `.osb` grows by roughly a line per command, so a preset that is fine
    /// in the editor can still be one nobody can ship.
    ///
    /// The ceiling is generous because the effects that need the most need it
    /// for a reason: weather reads as a field rather than as particles, and a
    /// field means hundreds of sprites. A storm is the heaviest thing here at
    /// around thirteen thousand lines — a large section of a storyboard, not an
    /// unusable one, and the count is the first parameter to turn down.
    @Test("no preset is ruinously expensive", arguments: EmitterEffect.presets)
    func presetsStayAffordable(preset: EffectPreset) {
        let commands = evaluator.evaluate(node(preset)).reduce(0) { $0 + $1.commands.count }

        #expect(commands < 16_000, "\(preset.id) writes \(commands) commands")
    }

    /// The bug this pins: a preset that covers the frame several times over is
    /// not an effect, it is a wall. Two of them shipped that way — `embers`
    /// used a noise texture at a hundred pixels a particle, and `dust` used a
    /// texture that is *already* a cloud of debris as though it were one speck.
    ///
    /// Coverage rather than particle count, because the two go together: a
    /// dense field of small particles is fine, and a handful of enormous ones
    /// is not. Weather is allowed more, since it is meant to fill the frame.
    @Test("no preset drowns the frame", arguments: EmitterEffect.presets)
    func presetsDoNotDrownTheFrame(preset: EffectPreset) {
        let node = EffectNode(
            id: preset.id, type: preset.effectType, name: preset.name,
            startTime: 0, duration: preset.duration, seed: 12, values: preset.values,
        )
        let prepared = StoryboardResolver.prepare(evaluator.evaluate(node))

        // The frame, in the source resolution the built-in textures use.
        let frameArea = 854.0 * 480.0
        let sourceSize = 512.0
        // Rain and snow are fields by definition; the rest are events in a
        // scene and have no business covering it more than once.
        let ceiling: Double = ["rain", "storm", "snow"].contains(preset.id) ? 6 : 2.5

        var worst = 0.0
        for fraction in stride(from: 0.1, through: 0.9, by: 0.2) {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: preset.duration * fraction, into: &states)

            let covered = states
                .filter { $0.visible && $0.opacity > 0.03 }
                .reduce(0.0) { $0 + pow($1.scaleX * sourceSize, 2) * $1.opacity }
            worst = max(worst, covered / frameArea)
        }

        #expect(worst < ceiling, "\(preset.id) covers \(String(format: "%.1f", worst))× the frame")
    }

    /// Across the whole library, not one effect's share of it.
    ///
    /// The panel keys its list on the id, so a repeat is silently dropped: the
    /// list came out a row short with a gap where the second should have been.
    /// A text preset and an emitter preset had both been called "shockwave",
    /// and checking each effect's presets separately could never have seen it.
    @Test("preset ids are unique")
    func idsAreUnique() {
        let all = TextEffect.presets + EmitterEffect.presets + EmitterEffect.compoundPresets
        let repeated = Dictionary(grouping: all.map(\.id), by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()

        #expect(repeated.isEmpty, "shared ids: \(repeated)")
    }

    // ─── What makes each one itself ──────────────────────────────────────────

    @Test("fire rises above where it was emitted")
    func fireRises() {
        let placed = node(EmitterEffect.fire)
        let prepared = StoryboardResolver.prepare(evaluator.evaluate(placed))

        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: 3000, into: &states)
        let visible = states.filter { $0.visible && $0.opacity > 0.02 }

        #expect(!visible.isEmpty)
        // y grows downwards in osu! space, so rising means a smaller y.
        #expect(visible.map(\.y).min()! < 400)
    }

    /// Smoke blocks light rather than adding to it — the one change that keeps
    /// it from looking like pale fire.
    @Test("smoke is not additive and fire is")
    func blendModesDiffer() {
        #expect(EmitterEffect.smoke.values[EmitterEffect.Param.additive] == .toggle(false))
        #expect(EmitterEffect.fire.values[EmitterEffect.Param.additive] == .toggle(true))
    }

    @Test("sparks fall while fire climbs")
    func gravityDirections() {
        guard case let .number(sparkGravity) = EmitterEffect.sparks.values[EmitterEffect.Param.gravity],
              case let .number(fireGravity) = EmitterEffect.fire.values[EmitterEffect.Param.gravity]
        else {
            Issue.record("expected numeric gravity")
            return
        }
        #expect(sparkGravity > 0)
        #expect(fireGravity < 0)
    }

    /// A single event, not a spray: every source of randomness is off.
    @Test("a shockwave is one uniform particle")
    func shockwaveIsSingular() {
        let sprites = evaluator.evaluate(node(EmitterEffect.shockwave))

        #expect(sprites.count == 1)
        #expect(sprites[0].commands.contains { $0.kind == .scale })
    }

    @Test("smoke grows while fire shrinks")
    func scaleDirections() {
        func scale(_ preset: EffectPreset, _ id: String) -> Double {
            guard case let .number(value) = preset.values[id] else { return 0 }
            return value
        }

        #expect(scale(EmitterEffect.smoke, EmitterEffect.Param.scaleEnd)
            > scale(EmitterEffect.smoke, EmitterEffect.Param.scaleStart))
        #expect(scale(EmitterEffect.fire, EmitterEffect.Param.scaleEnd)
            < scale(EmitterEffect.fire, EmitterEffect.Param.scaleStart))
    }

}
