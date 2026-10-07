import Foundation
import Testing

@testable import StoryboardCore

/// Particles a glyph throws off at its own moments: when it lands, while it
/// travels in, and as it leaves.
///
/// Read from resolved states, never by restating the particle's own
/// arithmetic — a test that recomputes the trajectory agrees with any
/// trajectory.
@Suite("Text glyph particles")
struct TextGlyphParticlesTests {
    private typealias P = TextEffect.Param
    private typealias Q = TextGlyphParticles.Param

    /// Every glyph rises in over 300ms, one 100ms behind the last, and fades
    /// out over the last 400ms of a three-second clip.
    private static let base: [String: EffectValue] = [
        P.stagger: .number(100), P.fadeIn: .number(300), P.fadeOut: .number(400), P.riseFrom: .number(40),
        Q.count: .number(6), Q.speed: .number(150), Q.life: .number(600),
    ]

    private func sprites(
        _ values: [String: EffectValue], text: String = "abc", seed: UInt64 = 8371, duration: Double = 3000,
    ) -> [StoryboardSprite] {
        let node = Phase1SnapshotTests.node(
            text: text, seed: seed, duration: duration,
            values: Self.base.merging(values) { _, new in new },
        )
        return Phase1SnapshotTests.production(node)
    }

    private func glyphs(_ sprites: [StoryboardSprite]) -> [StoryboardSprite] {
        sprites.filter { !$0.id.contains("/p") }
    }

    private func particles(_ sprites: [StoryboardSprite], of glyph: Int) -> [StoryboardSprite] {
        sprites.filter { $0.id.contains("/c\(glyph)/p") }
    }

    private func allParticles(_ sprites: [StoryboardSprite]) -> [StoryboardSprite] {
        sprites.filter { $0.id.contains("/p") }
    }

    private func state(_ sprite: StoryboardSprite, at time: Double) throws -> SpriteRenderState {
        let prepared = try #require(StoryboardResolver.prepare([sprite]).first)
        return StoryboardResolver.state(of: prepared, at: time)
    }

    private func birth(_ sprite: StoryboardSprite) -> Double {
        sprite.commands.filter { $0.kind != .parameter }.map(\.startTime).min() ?? .nan
    }

    private func death(_ sprite: StoryboardSprite) -> Double {
        sprite.commands.filter { $0.kind != .parameter }.map(\.endTime).max() ?? .nan
    }

    /// When a glyph finished arriving: the end of its fade-in, read from the
    /// glyph's own commands.
    private func landed(_ glyph: StoryboardSprite) throws -> Double {
        let fadeIn = try #require(glyph.commands.first { command in
            if case let .fade(start, end) = command.payload { return start == 0 && end > 0 }
            return false
        })
        return fadeIn.endTime
    }

    private func commandsOnly(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.map { String(reflecting: $0.commands) }
    }

    // ─── Inertness ───────────────────────────────────────────────────────────

    @Test("off by default: no particle sprites")
    func offByDefault() {
        #expect(allParticles(sprites([:])).isEmpty)
    }

    /// Turning particles on adds sprites and touches nothing else: the
    /// glyphs keep every command, Explode headings included.
    @Test("particles leave the glyphs untouched", arguments: ["Land", "Trail", "Disintegrate"])
    func glyphsUntouched(mode: String) {
        let exploding: [String: EffectValue] = [P.exit: .choice("Explode"), P.scatterX: .number(60)]
        let without = glyphs(sprites(exploding))
        let with = glyphs(sprites(exploding.merging([Q.mode: .choice(mode)]) { _, new in new }))
        #expect(commandsOnly(with) == commandsOnly(without))
    }

    // ─── Land ────────────────────────────────────────────────────────────────

    @Test("land: each glyph bursts when it lands, from where it landed")
    func landBurstsOnLanding() throws {
        let all = sprites([Q.mode: .choice("Land")])
        let letters = glyphs(all)
        #expect(letters.count == 3)
        for (index, glyph) in letters.enumerated() {
            let own = particles(all, of: index)
            #expect(own.count == 6)
            let landing = try landed(glyph)
            let resting = try state(glyph, at: landing)
            for particle in own {
                #expect(abs(birth(particle) - landing) < 40)
                let start = try state(particle, at: birth(particle))
                #expect(abs(start.x - resting.x) < 1)
                #expect(abs(start.y - resting.y) < 1)
            }
        }
    }

    @Test("particles travel and fade out over their life")
    func particlesTravelAndFade() throws {
        let all = sprites([Q.mode: .choice("Land")])
        for particle in allParticles(all) {
            let from = birth(particle)
            let to = death(particle)
            let start = try state(particle, at: from)
            let middle = try state(particle, at: (from + to) / 2)
            let distance = hypot(middle.x - start.x, middle.y - start.y)
            #expect(distance > 10)
            #expect(start.opacity > 0.9)
            let late = try state(particle, at: to)
            #expect(late.opacity < 0.05)
        }
    }

    @Test("gravity pulls the burst down")
    func gravityPulls() throws {
        func meanDrop(_ gravity: Double) throws -> Double {
            let all = sprites([Q.mode: .choice("Land"), Q.gravity: .number(gravity), Q.direction: .number(270)])
            let drops = try allParticles(all).map { particle in
                try state(particle, at: death(particle)).y - state(particle, at: birth(particle)).y
            }
            return drops.reduce(0, +) / Double(drops.count)
        }
        #expect(try meanDrop(800) > meanDrop(0) + 30)
    }

    // ─── Trail ───────────────────────────────────────────────────────────────

    @Test("trail: particles are born along the entrance, where the glyph is")
    func trailFollowsEntrance() throws {
        let all = sprites([Q.mode: .choice("Trail")])
        for (index, glyph) in glyphs(all).enumerated() {
            let own = particles(all, of: index)
            let births = own.map(birth)
            let landing = try landed(glyph)
            let arriving = landing - 300
            #expect(births.allSatisfy { $0 >= arriving - 1 && $0 <= landing + 1 })
            #expect((births.max() ?? 0) - (births.min() ?? 0) > 100)
            for particle in own {
                let at = birth(particle)
                let start = try state(particle, at: at)
                let source = try state(glyph, at: at)
                #expect(abs(start.x - source.x) < 1)
                #expect(abs(start.y - source.y) < 1)
            }
        }
    }

    // ─── Disintegrate ────────────────────────────────────────────────────────

    @Test("disintegrate: particles leave during the exit, from inside the glyph's box")
    func disintegrateDuringExit() throws {
        let all = sprites([Q.mode: .choice("Disintegrate")])
        for (index, glyph) in glyphs(all).enumerated() {
            let own = particles(all, of: index)
            #expect(own.count == 6)
            let exitStart = 3000.0 - 400
            for particle in own {
                let at = birth(particle)
                #expect(at >= exitStart - 1 && at <= 3000 + 1)
                let start = try state(particle, at: at)
                let source = try state(glyph, at: at)
                // Spread over the letter, not piled on its centre.
                #expect(abs(start.x - source.x) < 40)
                #expect(abs(start.y - source.y) < 40)
            }
            let offsets = try own.map { particle in
                try state(particle, at: birth(particle)).x - state(glyph, at: birth(particle)).x
            }
            #expect((offsets.max() ?? 0) - (offsets.min() ?? 0) > 2)
        }
    }

    // ─── Determinism and cost ────────────────────────────────────────────────

    @Test("the same seed draws the same burst; another seed, another")
    func seeded() {
        let values: [String: EffectValue] = [Q.mode: .choice("Land")]
        let a = commandsOnly(allParticles(sprites(values, seed: 1)))
        let b = commandsOnly(allParticles(sprites(values, seed: 1)))
        let c = commandsOnly(allParticles(sprites(values, seed: 2)))
        #expect(a == b)
        #expect(a != c)
    }

    @Test("a long line is capped as a whole")
    func capped() {
        let text = String(repeating: "abcdefghij", count: 12)
        let all = sprites([Q.mode: .choice("Land"), Q.count: .number(24)], text: text, duration: 20000)
        let count = allParticles(all).count
        #expect(count > 0)
        #expect(count <= TextGlyphParticles.maximumTotal)
    }

    @Test("colour and additive reach every particle")
    func colourAndBlend() {
        let all = sprites([
            Q.mode: .choice("Land"),
            Q.colour: .color(EffectColor(r: 255, g: 120, b: 30)),
            Q.additive: .toggle(true),
        ])
        for particle in allParticles(all) {
            #expect(particle.commands.contains { $0.kind == .color })
            #expect(particle.commands.contains {
                if case .parameter(.additive) = $0.payload { return true }
                return false
            })
        }
    }

    @Test("no particle holds two commands on one property at once", arguments: ["Land", "Trail", "Disintegrate"])
    func noOverlaps(mode: String) {
        let all = sprites([Q.mode: .choice(mode), Q.gravity: .number(400)])
        for particle in allParticles(all) {
            #expect(TextOverlapGuard.violations(particle).isEmpty, "\(particle.id)")
        }
    }

    @Test("particle controls show only when particles are on")
    func controlsHidden() throws {
        let parameters = TextEffect.descriptor.parameters.filter { $0.group == "Particles" }
        #expect(parameters.count > 1)
        for parameter in parameters where parameter.id != Q.mode {
            let condition = try #require(parameter.shownWhen)
            #expect(!condition.holds(in: [Q.mode: .choice("None")]))
            #expect(condition.holds(in: [Q.mode: .choice("Land")]))
        }
    }
}
