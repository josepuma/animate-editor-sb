import Foundation
import Testing

@testable import StoryboardCore

/// The Motion filters: Inertial Bounce, Squash & Stretch, Turbulence, Vortex
/// and Attractor.
///
/// Everything is read back through `StoryboardResolver`, the same code that
/// draws the sprite — a test that recomputed positions from the filter's own
/// formula would agree with any formula.
@Suite("Motion filters")
struct MotionFilterTests {
    // MARK: - Helpers

    private func context(_ filter: FilterDescriptor, _ values: [String: EffectValue] = [:], id: String = "f") -> FilterContext {
        FilterContext(
            descriptor: filter,
            node: FilterNode(id: id, type: filter.type, values: filter.defaultValues.merging(values) { _, new in new }),
        )
    }

    private func sprite(_ commands: [Command], id: String = "s", at x: Double = 320, _ y: Double = 240) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: "a.png",
            defaultX: x, defaultY: y, commands: commands,
        )
    }

    private func life(_ end: Double = 3000) -> Command {
        Command(easing: .linear, startTime: 0, endTime: end, payload: .fade(start: 1, end: 1))
    }

    private func move(_ from: (Double, Double), _ to: (Double, Double), _ start: Double = 0, _ end: Double = 500) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .move(startX: from.0, startY: from.1, endX: to.0, endY: to.1))
    }

    private func state(_ sprite: StoryboardSprite, _ time: Double) -> SpriteRenderState {
        StoryboardResolver.state(of: StoryboardResolver.prepare([sprite])[0], at: time)
    }

    private func positions(_ sprite: StoryboardSprite, every step: Double = 10, to end: Double = 3000) -> [Double] {
        stride(from: 0, through: end, by: step).map { state(sprite, $0).x }
    }

    private func overlaps(_ sprite: StoryboardSprite) -> Int {
        let families: [[CommandKind]] = [[.move, .moveX, .moveY], [.scale, .vectorScale], [.rotate], [.fade], [.color]]
        var count = 0
        for family in families {
            let commands = sprite.commands.filter { family.contains($0.kind) }
            for i in commands.indices {
                for j in commands.indices where j > i {
                    if commands[i].startTime < commands[j].endTime, commands[j].startTime < commands[i].endTime { count += 1 }
                }
            }
        }
        return count
    }

    // MARK: - Inertial Bounce

    @Test("a move overshoots in its own direction and settles back on its end")
    func bounceOvershoots() throws {
        let original = sprite([life(), move((0, 240), (200, 240))])
        let out = try #require(InertialBounceFilter().apply(to: [original], in: context(InertialBounceFilter.descriptor)).first)
        let xs = positions(out)
        #expect(xs.max()! > 205, "it should carry past 200")
        #expect(xs.min()! >= 0)
        #expect(abs(state(out, 3000).x - 200) < 0.01, "and come to rest where the move ended")
        // Back past the end too: a spring, not an overshoot-and-stop.
        #expect(xs.dropFirst(60).contains { $0 < 199 })
        #expect(overlaps(out) == 0)
    }

    @Test("the bounce never outlives the sprite")
    func bounceStaysInLife() throws {
        let original = sprite([life(700), move((0, 240), (200, 240))])
        let out = try #require(InertialBounceFilter().apply(to: [original], in: context(InertialBounceFilter.descriptor)).first)
        #expect(out.commands.map(\.endTime).max()! <= 700)
    }

    @Test("a move followed straight by another gets no bounce")
    func bounceNeedsRoom() throws {
        let original = sprite([life(), move((0, 240), (200, 240)), move((200, 240), (0, 240), 500, 1000)])
        let out = try #require(InertialBounceFilter().apply(to: [original], in: context(InertialBounceFilter.descriptor)).first)
        let early = out.commands.filter { $0.kind == .move && $0.endTime <= 500 }
        #expect(early.count == 1)
        #expect(overlaps(out) == 0)
    }

    @Test("Apply To limits the bounce to one property")
    func bounceScope() throws {
        let scaled = Command(easing: .linear, startTime: 0, endTime: 500, payload: .scale(start: 0.5, end: 1))
        let original = sprite([life(), move((0, 240), (200, 240)), scaled])
        let out = try #require(InertialBounceFilter().apply(
            to: [original],
            in: context(InertialBounceFilter.descriptor, [InertialBounceFilter.Param.target: .choice(InertialBounceFilter.Target.scale.rawValue)]),
        ).first)
        #expect(out.commands.filter { $0.kind == .move }.count == 1, "position untouched")
        #expect(out.commands.filter { $0.kind == .scale }.count > 1, "scale bounces")
    }

    @Test("zero amount changes nothing")
    func bounceInert() {
        let original = sprite([life(), move((0, 240), (200, 240))])
        let out = InertialBounceFilter().apply(to: [original], in: context(InertialBounceFilter.descriptor, [InertialBounceFilter.Param.amount: .number(0)]))
        #expect(out[0].commands.count == original.commands.count)
    }

    // MARK: - Squash & Stretch

    @Test("a fast horizontal move stretches wide and thins, keeping its area")
    func stretchHorizontal() throws {
        let original = sprite([life(), move((0, 240), (600, 240), 0, 500)])
        let out = try #require(SquashStretchFilter().apply(to: [original], in: context(SquashStretchFilter.descriptor)).first)
        let mid = state(out, 250)
        #expect(mid.scaleX > 1.1)
        #expect(mid.scaleY < 0.95)
        #expect(abs(mid.scaleX * mid.scaleY - 1) < 0.02)
        let still = state(out, 2000)
        #expect(abs(still.scaleX - 1) < 0.01 && abs(still.scaleY - 1) < 0.01, "at rest it is itself")
        #expect(!out.commands.contains { $0.kind == .scale }, "no _S beside the _V")
    }

    @Test("a vertical move stretches tall")
    func stretchVertical() throws {
        let original = sprite([life(), move((320, 0), (320, 600), 0, 500)])
        let out = try #require(SquashStretchFilter().apply(to: [original], in: context(SquashStretchFilter.descriptor)).first)
        let mid = state(out, 250)
        #expect(mid.scaleY > mid.scaleX)
    }

    @Test("the stretch multiplies the sprite's own size")
    func stretchKeepsSize() throws {
        let sized = Command(easing: .linear, startTime: 0, endTime: 0, payload: .vectorScale(startX: 2, startY: 0.5, endX: 2, endY: 0.5))
        let original = sprite([life(), sized, move((0, 240), (600, 240), 0, 500)])
        let out = try #require(SquashStretchFilter().apply(to: [original], in: context(SquashStretchFilter.descriptor)).first)
        let rest = state(out, 2000)
        #expect(abs(rest.scaleX - 2) < 0.01 && abs(rest.scaleY - 0.5) < 0.01)
        #expect(state(out, 250).scaleX > 2.2)
    }

    @Test("a still sprite is left alone")
    func stretchStill() {
        let original = sprite([life()])
        let out = SquashStretchFilter().apply(to: [original], in: context(SquashStretchFilter.descriptor))
        #expect(out[0].commands.count == original.commands.count)
    }

    // MARK: - Turbulence

    private func offset(_ sprite: StoryboardSprite, _ out: StoryboardSprite, _ time: Double) -> (Double, Double) {
        let a = state(sprite, time)
        let b = state(out, time)
        return (b.x - a.x, b.y - a.y)
    }

    @Test("neighbours drift together, distant sprites do not")
    func turbulenceIsCoherent() {
        let sprites = [sprite([life()], id: "a", at: 100, 200), sprite([life()], id: "b", at: 102, 200), sprite([life()], id: "c", at: 700, 200)]
        let out = TurbulenceFilter().apply(to: sprites, in: context(TurbulenceFilter.descriptor))
        var near = 0.0
        var far = 0.0
        for time in stride(from: 0.0, through: 3000, by: 250) {
            let a = offset(sprites[0], out[0], time)
            let b = offset(sprites[1], out[1], time)
            let c = offset(sprites[2], out[2], time)
            near += abs(a.0 - b.0) + abs(a.1 - b.1)
            far += abs(a.0 - c.0) + abs(a.1 - c.1)
        }
        #expect(far > near * 5, "near \(near), far \(far)")
        #expect(far > 10, "the field has to move things at all")
    }

    @Test("the field rides on the sprite's own movement")
    func turbulenceFolds() throws {
        let original = sprite([life(), move((0, 240), (600, 240), 0, 3000)])
        let out = try #require(TurbulenceFilter().apply(to: [original], in: context(TurbulenceFilter.descriptor)).first)
        let amount = 30.0
        for time in stride(from: 0.0, through: 3000, by: 100) {
            let (dx, dy) = offset(original, out, time)
            #expect(abs(dx) <= amount * 1.05 && abs(dy) <= amount * 1.05)
        }
        #expect(overlaps(out) == 0)
    }

    @Test("zero amount changes nothing")
    func turbulenceInert() {
        let original = sprite([life(), move((0, 240), (600, 240), 0, 3000)])
        let out = TurbulenceFilter().apply(to: [original], in: context(TurbulenceFilter.descriptor, [TurbulenceFilter.Param.amount: .number(0)]))
        #expect(String(reflecting: out[0]) == String(reflecting: original))
    }

    // MARK: - Vortex

    @Test("the vortex turns positions around its centre, strongest near it")
    func vortexTurns() {
        let values: [String: EffectValue] = [
            VortexFilter.Param.twist: .number(90), VortexFilter.Param.radius: .number(400),
        ]
        let inner = sprite([life()], id: "i", at: 420, 240)
        let outside = sprite([life()], id: "o", at: 900, 240)
        let out = VortexFilter().apply(to: [inner, outside], in: context(VortexFilter.descriptor, values))
        let turned = state(out[0], 0)
        // r = 100, falloff (1 − 100/400)² = 0.5625 → 50.6°.
        let angle = atan2(turned.y - 240, turned.x - 320) * 180 / .pi
        #expect(abs(abs(angle) - 50.625) < 0.5)
        #expect(abs(hypot(turned.x - 320, turned.y - 240) - 100) < 0.01, "a turn keeps the distance")
        #expect(state(out[1], 0).x == 900, "past the radius nothing moves")
    }

    @Test("spin keeps turning over time")
    func vortexSpins() {
        let values: [String: EffectValue] = [
            VortexFilter.Param.twist: .number(0), VortexFilter.Param.spin: .number(90), VortexFilter.Param.radius: .number(400),
        ]
        let out = VortexFilter().apply(to: [sprite([life()], at: 420, 240)], in: context(VortexFilter.descriptor, values))
        let early = state(out[0], 0)
        let late = state(out[0], 2000)
        #expect(abs(early.y - 240) < 0.01)
        #expect(abs(late.y - 240) > 50)
    }

    // MARK: - Attractor

    @Test("the attractor pulls toward its point once ramped, by strength and falloff")
    func attractorPulls() {
        let values: [String: EffectValue] = [
            AttractorFilter.Param.strength: .number(0.5), AttractorFilter.Param.radius: .number(400),
            AttractorFilter.Param.ramp: .number(1000),
        ]
        let near = sprite([life()], id: "n", at: 420, 240)
        let outside = sprite([life()], id: "o", at: 900, 240)
        let out = AttractorFilter().apply(to: [near, outside], in: context(AttractorFilter.descriptor, values))
        #expect(abs(state(out[0], 0).x - 420) < 0.01, "nothing before the ramp starts")
        // r = 100, falloff 1 − 100/400 = 0.75, k = 0.375 → 37.5 px closer.
        #expect(abs(state(out[0], 2000).x - 382.5) < 0.5)
        #expect(state(out[1], 2000).x == 900)
    }

    @Test("negative strength pushes away")
    func attractorRepels() {
        let out = AttractorFilter().apply(
            to: [sprite([life()], at: 420, 240)],
            in: context(AttractorFilter.descriptor, [AttractorFilter.Param.strength: .number(-0.5)]),
        )
        #expect(state(out[0], 2500).x > 420)
    }
}
