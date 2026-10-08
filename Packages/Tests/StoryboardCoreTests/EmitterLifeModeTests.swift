import Foundation
import Testing

@testable import StoryboardCore

/// Life measured as a share of the clip, not in milliseconds.
///
/// Reported as "every time I stretch these presets I have to change the
/// particle life of everything": a ring meant to last the clip was a particle
/// living a fixed 8000ms, so a clip stretched to 24 seconds lost its rings at
/// the eighth; and shafts built from copies cross-fading thinned into gaps,
/// because the same ten copies were spread over three times the time.
@Suite("Emitter life mode")
struct EmitterLifeModeTests {
    private let evaluator = EffectEvaluator()

    private func sprites(duration: Double, _ overrides: [String: EffectValue]) -> [StoryboardSprite] {
        var values = EmitterEffect.descriptor.defaultValues
        values[EmitterEffect.Param.count] = .integer(12)
        values[EmitterEffect.Param.lifeRandom] = .number(0)
        for (key, value) in overrides { values[key] = value }
        return evaluator.evaluate(EffectNode(
            id: "fx", type: EmitterEffect.descriptor.type, name: "fx",
            startTime: 0, duration: duration, seed: 5, values: values,
        ))
    }

    private func span(_ sprite: StoryboardSprite) -> (birth: Double, death: Double) {
        (sprite.commands.map(\.startTime).min() ?? 0, sprite.commands.map(\.endTime).max() ?? 0)
    }

    private static let clipMode: [String: EffectValue] = [
        EmitterEffect.Param.lifeMode: .choice(EmitterEffect.LifeMode.clip.rawValue),
    ]

    @Test("by default life is milliseconds, as it always was")
    func defaultIsMilliseconds() {
        #expect(EmitterEffect.descriptor.defaultValues[EmitterEffect.Param.lifeMode]
            == .choice(EmitterEffect.LifeMode.milliseconds.rawValue))
        for sprite in sprites(duration: 6000, [EmitterEffect.Param.life: .number(1500)]) {
            let s = span(sprite)
            #expect(abs((s.death - s.birth) - 1500) < 1e-6)
        }
    }

    /// A held element: born at the start, lasting to the end — however long
    /// the clip is stretched.
    @Test("a whole-clip life holds to the end of any clip", arguments: [2000.0, 9000, 30000])
    func holdsTheWholeClip(duration: Double) {
        var values = Self.clipMode
        values[EmitterEffect.Param.lifeFraction] = .number(1)
        values[EmitterEffect.Param.emission] = .choice(EmitterEffect.Emission.burst.rawValue)
        let made = sprites(duration: duration, values)
        #expect(!made.isEmpty)
        for sprite in made {
            let s = span(sprite)
            #expect(abs(s.birth) < 1e-6 && abs(s.death - duration) < 1e-6, "lives \(s.birth)…\(s.death) of \(duration)")
        }
    }

    /// Copies cross-fading keep the same overlap at any length: as many alive
    /// at once in a clip three times as long.
    @Test("a share of the clip keeps the overlap when stretched")
    func overlapSurvivesStretch() {
        func alive(_ duration: Double) -> Double {
            var values = Self.clipMode
            values[EmitterEffect.Param.lifeFraction] = .number(0.5)
            let made = sprites(duration: duration, values)
            let middle = duration / 2
            return Double(made.filter { span($0).birth <= middle && span($0).death >= middle }.count)
        }
        #expect(alive(4000) == alive(12000))
        #expect(alive(4000) >= 5)
    }

    /// The control that does not apply is not shown.
    @Test("only the life that applies is shown")
    func onlyTheLiveControlShows() throws {
        let parameters = EmitterEffect.descriptor.parameters
        let life = try #require(parameters.first { $0.id == EmitterEffect.Param.life })
        let fraction = try #require(parameters.first { $0.id == EmitterEffect.Param.lifeFraction })
        #expect(life.shownWhen?.parameter == EmitterEffect.Param.lifeMode)
        #expect(fraction.shownWhen?.parameter == EmitterEffect.Param.lifeMode)
    }
}
