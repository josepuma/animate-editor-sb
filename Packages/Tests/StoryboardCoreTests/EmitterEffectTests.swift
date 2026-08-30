import Foundation
import Testing

@testable import StoryboardCore

@Suite("EmitterEffect")
struct EmitterEffectTests {
    private func sprites(
        duration: Double = 2000,
        seed: UInt64 = 5,
        _ values: [String: EffectValue] = [:],
    ) -> [StoryboardSprite] {
        var merged: [String: EffectValue] = [EmitterEffect.Param.count: .integer(20)]
        for (key, value) in values { merged[key] = value }

        return EffectEvaluator().evaluate(EffectNode(
            id: "fx",
            type: "emitter",
            name: "Emitter",
            startTime: 0,
            duration: duration,
            seed: seed,
            values: merged,
        ))
    }

    // ─── Count ───────────────────────────────────────────────────────────────

    @Test("the emitter produces one sprite per particle")
    func countMatches() {
        #expect(sprites([EmitterEffect.Param.count: .integer(37)]).count == 37)
    }

    /// A particle is a sprite in a text file, not a point in a simulation, so
    /// the count has a ceiling that keeps the exported `.osb` openable.
    @Test("the particle count is capped")
    func countIsCapped() {
        let result = sprites([EmitterEffect.Param.count: .integer(50_000)])
        #expect(result.count == EmitterEffect.maximumCount)
    }

    @Test("a zero-length node produces nothing")
    func zeroDuration() {
        #expect(sprites(duration: 0).isEmpty)
    }

    @Test("an emitter with no sprite file produces nothing")
    func missingSpriteFile() {
        #expect(sprites([EmitterEffect.Param.sprite: .text("")]).isEmpty)
    }

    // ─── Emission ────────────────────────────────────────────────────────────

    @Test("a burst releases every particle at the start")
    func burstStartsTogether() {
        let result = sprites([EmitterEffect.Param.emission: .choice("Burst")])
        let births = result.compactMap { $0.commands.map(\.startTime).min() }

        #expect(births.allSatisfy { $0 == 0 })
    }

    /// Releasing at random makes a continuous emitter clump, which reads as
    /// stuttering rather than steady.
    @Test("a continuous emitter spreads births evenly across its duration")
    func continuousSpreadsEvenly() {
        let result = sprites(
            duration: 1000,
            [EmitterEffect.Param.count: .integer(10),
             EmitterEffect.Param.emission: .choice("Continuous")],
        )
        let births = result.compactMap { $0.commands.map(\.startTime).min() }.sorted()

        #expect(births.count == 10)
        for (index, birth) in births.enumerated() {
            #expect(abs(birth - Double(index) * 100) < 1e-9)
        }
    }

    // ─── Motion ──────────────────────────────────────────────────────────────

    /// `_M` interpolates in a straight line, so a straight path needs exactly
    /// one command — spending eight on it would bloat the file for nothing.
    @Test("a path with no gravity or drag is a single move command")
    func straightPathIsOneCommand() {
        let result = sprites([
            EmitterEffect.Param.gravity: .number(0),
            EmitterEffect.Param.drag: .number(0),
        ])
        let moves = result[0].commands.filter { $0.kind == .move }

        #expect(moves.count == 1)
    }

    @Test("gravity cuts the path into segments")
    func curvedPathIsSegmented() {
        let result = sprites([EmitterEffect.Param.gravity: .number(800)])
        let moves = result[0].commands.filter { $0.kind == .move }

        #expect(moves.count > 1)
    }

    @Test("consecutive move segments join end to end")
    func segmentsAreContinuous() {
        let result = sprites([EmitterEffect.Param.gravity: .number(800)])
        let moves = result[0].commands.filter { $0.kind == .move }

        for (previous, next) in zip(moves, moves.dropFirst()) {
            guard case let .move(_, _, endX, endY) = previous.payload,
                  case let .move(startX, startY, _, _) = next.payload
            else {
                Issue.record("expected move payloads")
                return
            }
            #expect(abs(endX - startX) < 1e-9)
            #expect(abs(endY - startY) < 1e-9)
            #expect(abs(previous.endTime - next.startTime) < 1e-9)
        }
    }

    @Test("gravity pulls particles downwards over their life")
    func gravityFalls() {
        let straight = sprites([
            EmitterEffect.Param.gravity: .number(0),
            EmitterEffect.Param.spread: .number(0),
            EmitterEffect.Param.direction: .number(0),
        ])
        let falling = sprites([
            EmitterEffect.Param.gravity: .number(2000),
            EmitterEffect.Param.spread: .number(0),
            EmitterEffect.Param.direction: .number(0),
        ])

        // In osu! space y grows downwards, so gravity raises the final y.
        #expect(finalY(of: falling[0]) > finalY(of: straight[0]))
    }

    @Test("drag shortens the distance travelled")
    func dragSlowsParticles() {
        let free = sprites([
            EmitterEffect.Param.drag: .number(0),
            EmitterEffect.Param.spread: .number(0),
            EmitterEffect.Param.velocityRandom: .number(0),
            EmitterEffect.Param.direction: .number(0),
        ])
        let dragged = sprites([
            EmitterEffect.Param.drag: .number(0.9),
            EmitterEffect.Param.spread: .number(0),
            EmitterEffect.Param.velocityRandom: .number(0),
            EmitterEffect.Param.direction: .number(0),
        ])

        #expect(finalX(of: dragged[0]) < finalX(of: free[0]))
    }

    // ─── Appearance ──────────────────────────────────────────────────────────

    /// Without a fade starting at birth, a sprite holds its default opacity
    /// from the beginning of the file — every particle visible before it exists.
    @Test("every particle has a fade starting at its birth")
    func fadeAnchorsAtBirth() {
        let result = sprites([EmitterEffect.Param.fadeIn: .number(0)])

        for sprite in result {
            let birth = sprite.commands.map(\.startTime).min()!
            let fades = sprite.commands.filter { $0.kind == .fade }
            #expect(fades.contains { $0.startTime == birth })
        }
    }

    @Test("fade in and fade out do not overlap")
    func fadesDoNotOverlap() {
        let result = sprites([
            EmitterEffect.Param.fadeIn: .number(0.4),
            EmitterEffect.Param.fadeOut: .number(0.4),
        ])
        let fades = result[0].commands.filter { $0.kind == .fade }.sorted { $0.startTime < $1.startTime }

        for (previous, next) in zip(fades, fades.dropFirst()) {
            #expect(next.startTime >= previous.endTime - 1e-9)
        }
    }

    /// Fades that would cross — both set high on a short life — must still
    /// resolve to one rise and one fall rather than fighting over the middle.
    @Test("fades that would overlap are clamped instead of crossing")
    func overlappingFadesAreClamped() {
        let result = sprites([
            EmitterEffect.Param.fadeIn: .number(0.9),
            EmitterEffect.Param.fadeOut: .number(0.9),
        ])
        let fades = result[0].commands.filter { $0.kind == .fade }.sorted { $0.startTime < $1.startTime }

        #expect(fades.count == 2)
        #expect(fades[1].startTime >= fades[0].endTime - 1e-9)
    }

    @Test("additive is only emitted when it is switched on")
    func additiveIsOptional() {
        let plain = sprites([EmitterEffect.Param.additive: .toggle(false)])
        let additive = sprites([EmitterEffect.Param.additive: .toggle(true)])

        #expect(plain[0].commands.allSatisfy { $0.kind != .parameter })
        #expect(additive[0].commands.contains { $0.kind == .parameter })
    }

    @Test("a white emitter writes no colour command")
    func whiteNeedsNoColourCommand() {
        let white = sprites([EmitterEffect.Param.color: .color(.white)])
        let tinted = sprites([EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 0, b: 0))])

        #expect(white[0].commands.allSatisfy { $0.kind != .color })
        #expect(tinted[0].commands.contains { $0.kind == .color })
    }

    @Test("a constant scale of 1 writes no scale command")
    func unitScaleNeedsNoCommand() {
        let result = sprites([
            EmitterEffect.Param.scaleStart: .number(1),
            EmitterEffect.Param.scaleEnd: .number(1),
            EmitterEffect.Param.scaleRandom: .number(0),
        ])

        #expect(result[0].commands.allSatisfy { $0.kind != .scale })
    }

    @Test("particles are emitted within the emitter's box")
    func particlesStartInsideTheBox() {
        let result = sprites([
            EmitterEffect.Param.x: .number(320),
            EmitterEffect.Param.y: .number(240),
            EmitterEffect.Param.width: .number(100),
            EmitterEffect.Param.height: .number(50),
        ])

        for sprite in result {
            #expect(abs(sprite.defaultX - 320) <= 50 + 1e-9)
            #expect(abs(sprite.defaultY - 240) <= 25 + 1e-9)
        }
    }

    /// Raising the count should add particles, not redraw the field — the
    /// reason each particle draws from its own derived stream.
    @Test("raising the count keeps the particles already placed")
    func countGrowsWithoutReshuffling() {
        let few = sprites([EmitterEffect.Param.count: .integer(10),
                           EmitterEffect.Param.emission: .choice("Burst")])
        let many = sprites([EmitterEffect.Param.count: .integer(40),
                            EmitterEffect.Param.emission: .choice("Burst")])

        for (small, large) in zip(few, many) {
            #expect(small.defaultX == large.defaultX)
            #expect(small.defaultY == large.defaultY)
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private func finalX(of sprite: StoryboardSprite) -> Double {
        guard case let .move(_, _, endX, _) = sprite.commands.last(where: { $0.kind == .move })?.payload
        else { return sprite.defaultX }
        return endX
    }

    private func finalY(of sprite: StoryboardSprite) -> Double {
        guard case let .move(_, _, _, endY) = sprite.commands.last(where: { $0.kind == .move })?.payload
        else { return sprite.defaultY }
        return endY
    }
}
