import Foundation
import Testing

@testable import StoryboardCore

/// Movement while a glyph holds, between its entrance and its exit.
///
/// Read from resolved states and written commands, never by restating the
/// motion's own arithmetic: a test that recomputes the sine agrees with any
/// sine.
@Suite("Text hold motion")
struct TextHoldMotionTests {
    private typealias P = TextEffect.Param

    static let modes = ["Wave", "Float", "Jitter", "Breathe", "Shake"]

    /// An entrance that moves, a fade-out, and nothing staggered: every glyph
    /// lands at 300 and starts leaving at 2600.
    private static let base: [String: EffectValue] = [
        P.fadeIn: .number(300), P.fadeOut: .number(400), P.riseFrom: .number(30),
        P.holdAmount: .number(12), P.holdBreathe: .number(30), P.holdSpeed: .number(1.5),
    ]
    private static let landed = 300.0
    private static let holdEnd = 2600.0

    private func sprites(
        _ values: [String: EffectValue], text: String = "ab cd", seed: UInt64 = 8371, duration: Double = 3000,
    ) -> [StoryboardSprite] {
        let node = Phase1SnapshotTests.node(
            text: text, seed: seed, duration: duration,
            values: Self.base.merging(values) { _, new in new },
        )
        return Phase1SnapshotTests.production(node)
    }

    private func state(_ sprite: StoryboardSprite, at time: Double) throws -> SpriteRenderState {
        try #require(StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time).first)
    }

    /// Commands only: every placement mints its own node id, which the
    /// sprite ids carry.
    private func dump(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.map { String(reflecting: $0.commands) }
    }

    private func reading(_ state: SpriteRenderState) -> [Double] {
        [state.x, state.y, state.scaleX, state.scaleY]
    }

    @Test("None writes nothing, whatever its own numbers say")
    func noneIsInert() {
        let plain = dump(sprites([:]))
        let none = dump(sprites([P.holdMotion: .choice("None")]))
        #expect(!plain.isEmpty && none == plain)
    }

    @Test("each mode moves the glyph while it holds", arguments: modes)
    func modesMove(mode: String) throws {
        let still = try #require(sprites([:]).first)
        let moving = try #require(sprites([P.holdMotion: .choice(mode)]).first)
        var differs = 0
        var readings: Set<[Double]> = []
        for step in 0..<40 {
            let time = Self.landed + 300 + Double(step) * 40
            let now = try reading(state(moving, at: time))
            readings.insert(now)
            if zip(now, try reading(state(still, at: time))).contains(where: { abs($0 - $1) > 0.01 }) { differs += 1 }
        }
        #expect(differs > 5, "\(mode) never leaves its rest")
        #expect(readings.count > 5, "\(mode) does not move over time")
    }

    /// The envelope brings the motion in from zero and back to zero, so the
    /// hold neither jumps off the entrance nor into the exit.
    @Test("the hold is continuous at both of its edges", arguments: modes)
    func continuousEdges(mode: String) throws {
        for sprite in sprites([P.holdMotion: .choice(mode), P.holdPhase: .number(80)]) {
            for edge in [Self.landed, Self.holdEnd] {
                let before = try reading(state(sprite, at: edge - 1))
                let after = try reading(state(sprite, at: edge + 1))
                #expect(abs(before[0] - after[0]) < 1.5 && abs(before[1] - after[1]) < 1.5, "\(mode) at \(edge)")
                #expect(abs(before[2] - after[2]) < 0.02, "\(mode) scale at \(edge)")
            }
        }
    }

    /// Travel and a position hold are one movement: the steps carry the travel
    /// rather than a second `_M` running under them, which osu! would let win.
    @Test("travel is folded into the hold", arguments: ["Wave", "Float", "Jitter", "Shake"])
    func travelFolded(mode: String) throws {
        let drawn = sprites([P.holdMotion: .choice(mode), P.driftX: .number(60), P.driftY: .number(-40)])
        for sprite in drawn {
            #expect(TextOverlapGuard.violations(sprite).isEmpty, "\(mode): \(TextOverlapGuard.violations(sprite))")
            let end = try state(sprite, at: Self.holdEnd - 0.5)
            #expect(abs(end.x - (sprite.defaultX + 60)) < 1 && abs(end.y - (sprite.defaultY - 40)) < 1)
            let middle = try state(sprite, at: (Self.landed + Self.holdEnd) / 2)
            #expect(abs(middle.x - (sprite.defaultX + 30)) < 13, "travel is halfway")
        }
    }

    /// Phase belongs to the unit: Word moves each word as one.
    @Test("glyphs of a word share their phase; words differ")
    func phasePerUnit() throws {
        let words = sprites([
            P.holdMotion: .choice("Wave"), P.holdPhase: .number(90), P.unit: .choice("Word"),
        ], text: "ab cd")
        let characters = sprites([
            P.holdMotion: .choice("Wave"), P.holdPhase: .number(90),
        ], text: "ab cd")
        let time = 1100.0
        func offset(_ sprite: StoryboardSprite) throws -> Double { try state(sprite, at: time).y - sprite.defaultY }
        #expect(abs(try offset(words[0]) - offset(words[1])) < 1e-6)
        #expect(abs(try offset(words[0]) - offset(words[2])) > 0.5)
        #expect(abs(try offset(characters[0]) - offset(characters[1])) > 0.5)
    }

    /// A long hold lengthens its steps rather than cutting them off: never
    /// more than 48, and the last still reaches the end of the hold.
    @Test("a long hold stays inside 48 steps and covers the whole hold", arguments: modes)
    func cap(mode: String) throws {
        let duration = 60000.0
        let holdEnd = duration - 400
        let drawn = sprites([P.holdMotion: .choice(mode), P.holdSpeed: .number(8)], duration: duration)
        for sprite in drawn {
            let steps = sprite.commands.filter {
                $0.startTime >= Self.landed && $0.endTime <= holdEnd && $0.kind != .fade
            }
            #expect(steps.count <= 48 && steps.count > 4, "\(mode): \(steps.count)")
            #expect(steps.map(\.endTime).max() == holdEnd, "\(mode) stops short")
            #expect(steps.map(\.startTime).min() == Self.landed)
            // Lengthened evenly, not cut: no step swallows the rest of the hold.
            let longest = steps.map { $0.endTime - $0.startTime }.max() ?? 0
            #expect(longest <= (holdEnd - Self.landed) / 20, "\(mode): a \(longest)ms step")
        }
    }

    @Test("the random modes follow the seed", arguments: ["Jitter", "Shake"])
    func seeded(mode: String) {
        let values: [String: EffectValue] = [P.holdMotion: .choice(mode)]
        let once = dump(sprites(values, seed: 5))
        #expect(once == dump(sprites(values, seed: 5)))
        #expect(once != dump(sprites(values, seed: 6)))
    }

    /// Turning a hold on never moves an exit's draws: Explode's headings and
    /// tumbles, and the entrance scatter, come out exactly as without it.
    @Test("a hold draws from its own stream", arguments: ["Jitter", "Shake", "Wave"])
    func isolated(mode: String) {
        let values: [String: EffectValue] = [
            P.exit: .choice("Explode"), P.scatterX: .number(40), P.scatterRotation: .number(30),
        ]
        let plain = sprites(values)
        let held = sprites(values.merging([P.holdMotion: .choice(mode)]) { _, new in new })
        for (a, b) in zip(plain, held) {
            let edges = { (sprite: StoryboardSprite) in
                sprite.commands.filter { $0.endTime <= Self.landed || $0.startTime >= Self.holdEnd }
                    .map { String(reflecting: $0) }
            }
            #expect(edges(a) == edges(b))
            #expect(!edges(a).isEmpty)
        }
    }
}
