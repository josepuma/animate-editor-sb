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
