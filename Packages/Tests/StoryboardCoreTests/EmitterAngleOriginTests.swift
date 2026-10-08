import Foundation
import Testing

@testable import StoryboardCore

/// `Angle` and `Origin`: one tilt for every particle, and the point on the
/// sprite it hangs from, turns about and grows from.
@Suite("Emitter angle and origin")
struct EmitterAngleOriginTests {
    private let evaluator = EffectEvaluator()

    private func sprites(_ overrides: [String: EffectValue]) -> [StoryboardSprite] {
        var values = EmitterEffect.descriptor.defaultValues
        values[EmitterEffect.Param.count] = .integer(12)
        for (key, value) in overrides { values[key] = value }
        return evaluator.evaluate(EffectNode(
            id: "fx", type: EmitterEffect.descriptor.type, name: "fx",
            startTime: 0, duration: 2000, seed: 3, values: values,
        ))
    }

    private func rotations(_ sprite: StoryboardSprite) -> [Double] {
        sprite.commands.compactMap { command in
            guard case let .rotate(start, _) = command.payload else { return nil }
            return start
        }
    }

    /// Added to a library full of placed effects: at their defaults neither
    /// may change a thing.
    @Test("at their defaults they change nothing")
    func defaultsAreInert() {
        let made = sprites([:])
        #expect(made.allSatisfy { $0.origin == .centre })
        #expect(made.allSatisfy { rotations($0).isEmpty })
    }

    /// One tilt, the same for every particle — unlike `Rotation Random`,
    /// which leans each one its own way.
    @Test("angle tilts every particle by the same amount")
    func angleIsShared() {
        let made = sprites([EmitterEffect.Param.angle: .number(-28)])
        let expected = -28 * Double.pi / 180
        #expect(!made.isEmpty)
        for sprite in made {
            #expect(rotations(sprite).count == 1)
            #expect(abs((rotations(sprite).first ?? 0) - expected) < 1e-9)
        }
    }

    /// The tilt sits underneath the random one, not instead of it.
    @Test("angle adds to the random tilt")
    func angleAddsToRandom() {
        let random = sprites([EmitterEffect.Param.rotation: .number(40)])
        let both = sprites([EmitterEffect.Param.rotation: .number(40), EmitterEffect.Param.angle: .number(10)])
        let offset = 10 * Double.pi / 180
        for (a, b) in zip(random, both) {
            #expect(abs((rotations(b).first ?? 0) - (rotations(a).first ?? 0) - offset) < 1e-9)
        }
    }

    /// The origin goes on the sprite, where osu! turns and scales about it —
    /// and the position stays where it was: anchoring a shaft at its source
    /// must not also move it.
    @Test("origin anchors the sprite without moving it")
    func originAnchors() {
        let centred = sprites([:])
        let anchored = sprites([EmitterEffect.Param.origin: .choice(Origin.topCentre.rawValue)])
        #expect(anchored.allSatisfy { $0.origin == .topCentre })
        for (a, b) in zip(centred, anchored) {
            #expect(a.defaultX == b.defaultX && a.defaultY == b.defaultY)
        }
    }
}
