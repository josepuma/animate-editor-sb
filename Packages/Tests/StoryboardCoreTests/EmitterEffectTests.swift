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

    // ─── Colour over life ────────────────────────────────────────────────────
    //
    // `_C` interpolates on its own, so a ramp between two colours costs one
    // command. Every command here is multiplied by the particle count in the
    // exported file, which is why the midpoint is opt-in rather than always on.

    @Test("a two-colour ramp costs one command")
    func rampIsOneCommand() {
        let result = sprites([
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 200, b: 60)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 120, g: 20, b: 0)),
        ])
        let colours = result[0].commands.filter { $0.kind == .color }

        #expect(colours.count == 1)
        guard case let .color(r1, g1, b1, r2, g2, b2) = colours[0].payload else {
            Issue.record("expected a colour payload")
            return
        }
        #expect((r1, g1, b1) == (255, 200, 60))
        #expect((r2, g2, b2) == (120, 20, 0))
    }

    @Test("a ramp runs the whole life of its particle")
    func rampSpansTheLife() {
        let result = sprites([
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 0, b: 0)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 0, g: 0, b: 255)),
        ])
        let sprite = result[0]
        let colour = sprite.commands.first { $0.kind == .color }!
        let birth = sprite.commands.map(\.startTime).min()!
        let death = sprite.commands.map(\.endTime).max()!

        #expect(colour.startTime == birth)
        #expect(colour.endTime == death)
    }

    @Test("a midpoint splits the ramp in two")
    func midpointSplitsTheRamp() {
        let result = sprites([
            EmitterEffect.Param.usesColorMid: .toggle(true),
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
            EmitterEffect.Param.colorMid: .color(EffectColor(r: 255, g: 150, b: 40)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 120, g: 20, b: 0)),
        ])
        let colours = result[0].commands
            .filter { $0.kind == .color }
            .sorted { $0.startTime < $1.startTime }

        #expect(colours.count == 2)
        // The halves meet, so the ramp reads as continuous rather than jumping.
        #expect(colours[0].endTime == colours[1].startTime)
    }

    /// Switched off, the midpoint costs nothing — the point of making it
    /// opt-in.
    @Test("an unused midpoint adds no command")
    func unusedMidpointCostsNothing() {
        let withMid = sprites([
            EmitterEffect.Param.usesColorMid: .toggle(false),
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 0, b: 0)),
            EmitterEffect.Param.colorMid: .color(EffectColor(r: 0, g: 255, b: 0)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 0, g: 0, b: 255)),
        ])

        #expect(withMid[0].commands.filter { $0.kind == .color }.count == 1)
    }

    // ─── Colour variety ──────────────────────────────────────────────────────
    //
    // The ramp runs over a particle's life, so on its own every particle is the
    // same colour at the same moment — right for fire, where the field cools
    // together, and wrong for confetti, which is many colours at once.

    @Test("colour variety gives particles different colours")
    func varietySpreadsColours() {
        let plain = sprites([
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 90, b: 120)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 255, g: 90, b: 120)),
            EmitterEffect.Param.colorVariety: .number(0),
        ])
        let varied = sprites([
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 90, b: 120)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 255, g: 90, b: 120)),
            EmitterEffect.Param.colorVariety: .number(1),
        ])

        #expect(distinctColours(plain) == 1)
        #expect(distinctColours(varied) > 5)
    }

    /// Nudging the channels independently walks towards grey, which is the one
    /// direction a field of confetti must not go. Rotating hue keeps every
    /// particle as saturated as the colour it came from.
    @Test("variety rotates hue rather than washing colour out")
    func varietyKeepsSaturation() {
        let varied = sprites([
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 90, b: 120)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 255, g: 90, b: 120)),
            EmitterEffect.Param.colorVariety: .number(1),
        ])

        for sprite in varied {
            guard case let .color(r, g, b, _, _, _) = sprite.commands
                .first(where: { $0.kind == .color })?.payload
            else { continue }

            let high = max(r, max(g, b))
            let low = min(r, min(g, b))
            // The source colour spans 90…255; every rotation of it should keep
            // roughly that spread rather than collapsing towards a grey.
            #expect(high - low > 100)
        }
    }

    @Test("a grey colour has no hue to vary")
    func greyStaysGrey() {
        let grey = EffectColor(r: 128, g: 128, b: 128)
        #expect(grey.varied(by: 0.5) == grey)
    }

    private func distinctColours(_ sprites: [StoryboardSprite]) -> Int {
        var seen: Set<String> = []
        for sprite in sprites {
            guard case let .color(r, g, b, _, _, _) = sprite.commands
                .first(where: { $0.kind == .color })?.payload
            else { continue }
            seen.insert("\(Int(r)),\(Int(g)),\(Int(b))")
        }
        return seen.count
    }

    @Test("a white emitter writes no colour command")
    func whiteNeedsNoColourCommand() {
        let white = sprites([
            EmitterEffect.Param.color: .color(.white),
            EmitterEffect.Param.colorEnd: .color(.white),
        ])
        let tinted = sprites([
            EmitterEffect.Param.color: .color(EffectColor(r: 255, g: 0, b: 0)),
            EmitterEffect.Param.colorEnd: .color(EffectColor(r: 255, g: 0, b: 0)),
        ])

        #expect(white[0].commands.allSatisfy { $0.kind != .color })
        #expect(tinted[0].commands.contains { $0.kind == .color })
    }

    /// Uniform scale is the wrong tool for anything that moves fast: buying
    /// length with `_S` buys width with it, which is what turned the rain into
    /// grey bars.
    @Test("stretch writes a vector scale instead of a uniform one")
    func stretchUsesVectorScale() {
        let stretched = sprites([
            EmitterEffect.Param.stretch: .number(8),
            EmitterEffect.Param.scaleStart: .number(0.1),
            EmitterEffect.Param.scaleEnd: .number(0.1),
        ])
        let commands = stretched[0].commands

        #expect(commands.allSatisfy { $0.kind != .scale })
        guard case let .vectorScale(startX, startY, _, _) = commands
            .first(where: { $0.kind == .vectorScale })?.payload
        else {
            Issue.record("expected a vector scale")
            return
        }
        #expect(abs(startY / startX - 8) < 1e-9)
    }

    /// `_V` costs the same as `_S` but writes twice the numbers, and a
    /// storyboard is a text file.
    @Test("no stretch keeps the cheaper uniform scale")
    func noStretchStaysUniform() {
        let plain = sprites([
            EmitterEffect.Param.stretch: .number(1),
            EmitterEffect.Param.scaleStart: .number(0.5),
            EmitterEffect.Param.scaleEnd: .number(0.2),
        ])

        #expect(plain[0].commands.contains { $0.kind == .scale })
        #expect(plain[0].commands.allSatisfy { $0.kind != .vectorScale })
    }

    /// Without this, rotation is pure noise and a shaped texture faces a random
    /// way regardless of travel — a raindrop falling at an angle drawn upright,
    /// sliding sideways through its own path.
    @Test("aligned particles point along their direction of travel")
    func alignmentFollowsDirection() {
        // Not 90°: the shapes point up, so aligning to 90° is a zero rotation
        // and writes no command — correct, and indistinguishable from not
        // aligning at all, which makes it the one angle that proves nothing.
        for direction in [135.0, 270.0, 45.0] {
            let result = sprites([
                EmitterEffect.Param.alignToMotion: .toggle(true),
                EmitterEffect.Param.direction: .number(direction),
                EmitterEffect.Param.spread: .number(0),
                EmitterEffect.Param.rotation: .number(0),
                EmitterEffect.Param.spin: .number(0),
            ])

            guard case let .rotate(start, _) = result[0].commands
                .first(where: { $0.kind == .rotate })?.payload
            else {
                Issue.record("expected a rotate command at direction \(direction)")
                return
            }

            // The built-in shapes point up, so aligned means a quarter turn off
            // the travel angle.
            let expected = (direction - 90) * .pi / 180
            #expect(abs(start - expected) < 1e-9)
        }
    }

    @Test("unaligned particles rotate only by their own jitter")
    func withoutAlignmentRotationIsNoise() {
        let result = sprites([
            EmitterEffect.Param.alignToMotion: .toggle(false),
            EmitterEffect.Param.direction: .number(135),
            EmitterEffect.Param.spread: .number(0),
            EmitterEffect.Param.rotation: .number(0),
            EmitterEffect.Param.spin: .number(0),
        ])

        // No jitter and no alignment: nothing to rotate, so nothing is written.
        #expect(result[0].commands.allSatisfy { $0.kind != .rotate })
    }

    // ─── Repeating bursts ────────────────────────────────────────────────────

    /// An even drip is right for fire and wrong for anything that *happens*:
    /// lightning strikes two or three times in a moment, then stops.
    @Test("repeating bursts release in clumps")
    func burstsClump() {
        let result = sprites(
            duration: 3000,
            [EmitterEffect.Param.count: .integer(12),
             EmitterEffect.Param.emission: .choice("Repeating Bursts"),
             EmitterEffect.Param.burstCount: .integer(3)],
        )
        let births = Set(result.compactMap { $0.commands.map(\.startTime).min() })

        // Twelve particles, three moments.
        #expect(births.count == 3)
        #expect(result.count == 12)
    }

    @Test("a single burst group behaves like a plain burst")
    func oneGroupIsABurst() {
        let result = sprites([
            EmitterEffect.Param.emission: .choice("Repeating Bursts"),
            EmitterEffect.Param.burstCount: .integer(1),
        ])
        let births = Set(result.compactMap { $0.commands.map(\.startTime).min() })

        #expect(births == [0])
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

/// A clip's transform moves everything it produced as one object.
///
/// The sprites keep their arrangement, the way a group does in any editor —
/// which is what a transform means to someone looking at a clip: not "where the
/// emitter is", but "where this thing is".
///
/// osu! has no nested sprites, so there is no group to move: every sprite is
/// moved individually and a rotation is baked into each one's path. That is
/// what it costs, and the editor says so before a file is written.
@Suite("Group transform")
struct GroupTransformTests {
    private let evaluator = EffectEvaluator()

    private func emitter(duration: Double = 4000, _ build: (inout EffectNode) -> Void) -> EffectNode {
        var document = EffectDocument()
        var node = document.add(EmitterEffect.descriptor, at: 0, duration: duration)
        node.values[EmitterEffect.Param.count] = .integer(6)
        node.values[EmitterEffect.Param.emission] = .choice("Burst")
        node.values[EmitterEffect.Param.width] = .number(100)
        node.values[EmitterEffect.Param.velocity] = .number(0)
        node.values[EmitterEffect.Param.gravity] = .number(0)
        // Alive for the whole clip: a transform is about where sprites are, and
        // a burst that has already died has no position to check.
        node.values[EmitterEffect.Param.life] = .number(duration)
        node.values[EmitterEffect.Param.lifeRandom] = .number(0)
        node.values[EmitterEffect.Param.fadeOut] = .number(0.05)
        build(&node)
        return node
    }

    private func positions(of node: EffectNode, at time: Double) -> [(x: Double, y: Double)] {
        let prepared = StoryboardResolver.prepare(evaluator.evaluate(node))
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: time, into: &states)
        return states.map { ($0.x, $0.y) }
    }

    /// The whole clip travels, and its sprites travel with it.
    @Test("a moving clip carries its sprites")
    func clipCarriesItsSprites() {
        let travelling = emitter { node in
            node.transform[.x] = KeyframeTrack([
                Keyframe(time: 0, value: 320),
                Keyframe(time: 4000, value: 620),
            ])
        }

        let start = positions(of: travelling, at: 100).map(\.x)
        let end = positions(of: travelling, at: 3900).map(\.x)

        #expect(!start.isEmpty)
        #expect(end.min()! > start.max()!)
    }

    /// Their arrangement survives the trip: this is a group moving, not sprites
    /// converging on a point.
    @Test("sprites keep their spacing while the clip moves")
    func spacingIsPreserved() {
        let travelling = emitter { node in
            node.transform[.x] = KeyframeTrack([
                Keyframe(time: 0, value: 320),
                Keyframe(time: 4000, value: 620),
            ])
        }

        let start = positions(of: travelling, at: 100).map(\.x).sorted()
        let end = positions(of: travelling, at: 3900).map(\.x).sorted()

        let startSpread = start.last! - start.first!
        let endSpread = end.last! - end.first!
        #expect(abs(startSpread - endSpread) < 1)
    }

    /// A rotation turns the clip about its own centre, not the canvas — a clip
    /// placed off to one side would otherwise swing across the whole screen.
    @Test("a rotating clip turns about its own centre")
    func rotatesAboutItsCentre() {
        let turning = emitter { node in
            node.transform[.rotation] = KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 4000, value: 180),
            ])
        }

        let before = positions(of: turning, at: 100)
        let after = positions(of: turning, at: 3900)

        // The centre stays put; the sprites around it have swapped sides.
        let centreBefore = before.reduce(0.0) { $0 + $1.x } / Double(before.count)
        let centreAfter = after.reduce(0.0) { $0 + $1.x } / Double(after.count)
        #expect(abs(centreBefore - centreAfter) < 5)
        #expect(before.map(\.x).max()! != after.map(\.x).max()!)
    }

    @Test("a scaled clip scales its sprites")
    func scaleReachesSprites() {
        let plain = emitter { $0.transform[value: .scale] = 1 }
        let doubled = emitter { $0.transform[value: .scale] = 2 }

        let prepared = StoryboardResolver.prepare(evaluator.evaluate(doubled))
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: 1000, into: &states)

        let plainPrepared = StoryboardResolver.prepare(evaluator.evaluate(plain))
        var plainStates: [SpriteRenderState] = []
        StoryboardResolver.resolve(plainPrepared, at: 1000, into: &plainStates)

        #expect(!states.isEmpty)
        #expect(abs(states[0].scaleX - plainStates[0].scaleX * 2) < 1e-9)
    }

    /// The bug this pins: motion was rebuilt by sampling the path and writing
    /// every piece as linear. With one segment — a plain move, no rotation to
    /// bend it — the sampling *was* the whole span, and an ease out came
    /// through as a straight line.
    @Test("a keyframe's easing reaches its command")
    func easingSurvives() {
        var document = EffectDocument()
        var node = document.add(ImageEffect.descriptor, at: 0, duration: 2000)
        node.values[ImageEffect.Param.sprite] = .text("a.png")
        node.transform[.x] = KeyframeTrack([
            Keyframe(time: 0, value: 0, easing: .out),
            Keyframe(time: 2000, value: 400),
        ])
        document[node.id] = node

        let moves = evaluator.evaluate(document)[0].commands
            .filter { $0.kind == .move || $0.kind == .moveX }

        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.easing == .out })
    }

    @Test("an eased move is ahead of a linear one at its midpoint")
    func easingChangesTheMotion() {
        func midpoint(_ easing: Easing) -> Double {
            var document = EffectDocument()
            var node = document.add(ImageEffect.descriptor, at: 0, duration: 2000)
            node.values[ImageEffect.Param.sprite] = .text("a.png")
            node.transform[.x] = KeyframeTrack([
                Keyframe(time: 0, value: 0, easing: easing),
                Keyframe(time: 2000, value: 400),
            ])
            document[node.id] = node

            let prepared = StoryboardResolver.prepare(evaluator.evaluate(document))
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: 1000, into: &states)
            return states.first?.x ?? 0
        }

        #expect(abs(midpoint(.linear) - 200) < 1e-9)
        #expect(midpoint(.out) > 250)
        #expect(midpoint(.in) < 150)
    }

    /// Each span carries its own curve, so a key partway through changes only
    /// what follows it.
    @Test("each keyframe span carries its own easing")
    func perSpanEasing() {
        var document = EffectDocument()
        var node = document.add(ImageEffect.descriptor, at: 0, duration: 3000)
        node.values[ImageEffect.Param.sprite] = .text("a.png")
        node.transform[.x] = KeyframeTrack([
            Keyframe(time: 0, value: 0, easing: .out),
            Keyframe(time: 1500, value: 200, easing: .in),
            Keyframe(time: 3000, value: 400),
        ])
        document[node.id] = node

        let moves = evaluator.evaluate(document)[0].commands
            .filter { $0.kind == .move || $0.kind == .moveX }
            .sorted { $0.startTime < $1.startTime }

        #expect(moves.count == 2)
        #expect(moves[0].easing == .out)
        #expect(moves[1].easing == .in)
    }

    /// A clip that sits still should cost exactly what it did before transforms
    /// existed.
    @Test("an untouched transform adds no commands")
    func untouchedIsFree() {
        let still = emitter { _ in }
        let commands = evaluator.evaluate(still).reduce(0) { $0 + $1.commands.count }

        var bare = still
        bare.transform = Transform()
        let bareCommands = evaluator.evaluate(bare).reduce(0) { $0 + $1.commands.count }

        #expect(commands == bareCommands)
    }

    /// A rotation curves every path, and a curve costs several commands where
    /// the line cost one. Worth knowing before a file is written.
    @Test("a rotation costs commands, and the estimate says so")
    func rotationCosts() {
        var rotating = Transform()
        rotating[.rotation] = KeyframeTrack([
            Keyframe(time: 0, value: 0),
            Keyframe(time: 1000, value: 90),
        ])

        #expect(GroupTransform.estimatedCommandsPerSprite(rotating) >= 8)
        #expect(GroupTransform.estimatedCommandsPerSprite(Transform()) == 0)
    }
}
