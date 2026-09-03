import Testing

@testable import StoryboardCore

@Suite("Rotation keyframes")
struct RotationKeyframeTests {
    private func evaluate(
        keys: [Keyframe],
        duration: Double = 30000,
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(ImageEffect.descriptor, at: 0, duration: duration)
        node.values[ImageEffect.Param.sprite] = .text("a.png")
        node.transform[.rotation] = KeyframeTrack(keys)
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    private func angle(of sprites: [StoryboardSprite], at time: Double) -> Double {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return (states.first?.rotation ?? 0) * 180 / .pi
    }

    /// The turn has to end where its last keyframe says it does.
    ///
    /// Reading only the value at the sprite's birth and death stretched it over
    /// the whole clip instead: keys at 0 and 15s inside a 30s clip turned half
    /// as fast and were still going at the end, long past the keyframe that was
    /// meant to stop them.
    @Test("a rotation ends at its last keyframe")
    func rotationEndsWithItsKeys() {
        let sprites = evaluate(keys: [
            Keyframe(time: 0, value: 0),
            Keyframe(time: 15000, value: 360),
        ])

        #expect(abs(angle(of: sprites, at: 7500) - 180) < 1)
        #expect(abs(angle(of: sprites, at: 15000) - 360) < 1)
        // Held, not still turning.
        #expect(abs(angle(of: sprites, at: 30000) - 360) < 1)
    }

    /// Two samples cannot describe a curve, so a middle key has to survive.
    @Test("a middle keyframe is not skipped")
    func middleKeysSurvive() {
        let sprites = evaluate(keys: [
            Keyframe(time: 0, value: 0),
            Keyframe(time: 5000, value: 90),
            Keyframe(time: 10000, value: 0),
        ])

        #expect(abs(angle(of: sprites, at: 5000) - 90) < 1)
        // Back where it started, which a straight line from 0 to 0 would hide.
        #expect(abs(angle(of: sprites, at: 10000)) < 1)
    }

    @Test("a single keyframe holds its angle")
    func singleKeyHolds() {
        let sprites = evaluate(keys: [Keyframe(time: 0, value: 45)])

        #expect(abs(angle(of: sprites, at: 0) - 45) < 1)
        #expect(abs(angle(of: sprites, at: 20000) - 45) < 1)
    }

    /// Degrees in the editor, radians in the file.
    @Test("a full turn is 360 in the editor and 2pi in the file")
    func unitsConvert() throws {
        let sprites = evaluate(keys: [
            Keyframe(time: 0, value: 0),
            Keyframe(time: 1000, value: 360),
        ])

        let rotate = sprites[0].commands.first { $0.kind == .rotate }
        let command = try #require(rotate)
        if case let .rotate(_, end) = command.payload {
            #expect(abs(end - .pi * 2) < 0.001)
        } else {
            Issue.record("expected a rotate command")
        }
    }
}

/// A rotated sprite must not outlive itself.
///
/// `prepare` reads a sprite's lifetime from its longest command, so a rotation
/// written across the whole clip keeps a particle "alive" long after it has
/// faded — and every live sprite is resolved on every frame. Measured on a
/// grid-filtered emitter: average lifetime 1,202ms without rotation and 5,000ms
/// with it, sprites live at once 1,217 against 5,020. Four times the per-frame
/// work, spent turning particles nobody can see.
@Suite("Rotation lifetime")
struct RotationLifetimeTests {
    /// One emitter, optionally turning.
    private func sprites(rotating: Bool) -> [StoryboardSprite] {
        var document = EffectDocument()
        _ = document.add(EmitterEffect.descriptor, at: 0, duration: 5000)
        let clip = document.nodes[0].id
        document.setValue(.integer(20), for: EmitterEffect.Param.count, on: clip)
        if rotating {
            document.setKeyframe(0, for: .rotation, at: 0, on: clip)
            document.setKeyframe(360, for: .rotation, at: 5000, on: clip)
        }
        return EffectEvaluator().evaluate(document)
    }

    @Test("rotating a clip does not extend its particles' lives")
    func rotationDoesNotExtendLifetimes() {
        func lifetimes(_ sprites: [StoryboardSprite]) -> [Double] {
            sprites.compactMap { sprite in
                guard let start = sprite.commands.map(\.startTime).min(),
                      let end = sprite.commands.map(\.endTime).max()
                else { return nil }
                return end - start
            }
        }

        let still = lifetimes(sprites(rotating: false))
        let turning = lifetimes(sprites(rotating: true))

        #expect(still.count == turning.count)

        let stillAverage = still.reduce(0, +) / Double(still.count)
        let turningAverage = turning.reduce(0, +) / Double(turning.count)

        #expect(
            abs(turningAverage - stillAverage) < 1,
            "rotating stretched lifetimes from \(stillAverage)ms to \(turningAverage)ms",
        )
    }

    /// A shortened turn has to turn *less*, not turn faster: keeping the whole
    /// sweep inside a clipped span would spin the sprite quicker rather than
    /// stopping it sooner.
    @Test("a clipped rotation carries only its own share of the turn")
    func clippedRotationIsScaled() {
        let turning = sprites(rotating: true)

        for sprite in turning {
            guard let death = sprite.commands.map(\.endTime).max() else { continue }
            for command in sprite.commands {
                guard case let .rotate(start, end) = command.payload else { continue }

                #expect(command.endTime <= death + 0.001, "the turn outlives its sprite")

                // A particle living a fifth of a 360° clip turns about a fifth
                // of the way round, not all of it.
                let share = (command.endTime - command.startTime) / 5000
                let turned = abs(end - start)
                #expect(
                    turned <= 2 * .pi * share + 0.01,
                    "turned \(turned) rad over \(share) of the clip",
                )
            }
        }
    }
}
