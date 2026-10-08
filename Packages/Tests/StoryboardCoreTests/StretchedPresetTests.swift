import Foundation
import Testing

@testable import StoryboardCore

/// A preset has to survive its clip being stretched.
///
/// "Every time I stretch these clips I have to change the particle life of
/// everything": held rings and flowers were particles with a fixed life in
/// milliseconds, so stretched past the preset's own length they vanished
/// part-way through; light shafts built from copies cross-fading thinned
/// into gaps. Every emitter that measures its life against the clip is held
/// here to what that promises, at three times the preset's length.
@Suite("Stretched presets")
struct StretchedPresetTests {
    private let evaluator = EffectEvaluator()

    /// Every emitter — a preset's own and each layer's — whose life is a
    /// share of the clip, with the preset it belongs to.
    private static let clipLived: [(preset: String, emitter: String)] = {
        var found: [(String, String)] = []
        for preset in EmitterEffect.presets + EmitterEffect.compoundPresets {
            let emitters = [("parent", preset.values)] + preset.layers.map { ($0.name, $0.values) }
            for (name, values) in emitters
            where values[EmitterEffect.Param.lifeMode] == .choice(EmitterEffect.LifeMode.clip.rawValue) {
                found.append((preset.id, name))
            }
        }
        return found
    }()

    private func values(_ presetID: String, _ emitter: String) throws -> [String: EffectValue] {
        let preset = try #require((EmitterEffect.presets + EmitterEffect.compoundPresets).first { $0.id == presetID })
        return emitter == "parent" ? preset.values : try #require(preset.layers.first { $0.name == emitter }).values
    }

    private func duration(_ presetID: String) throws -> Double {
        try #require((EmitterEffect.presets + EmitterEffect.compoundPresets).first { $0.id == presetID }).duration
    }

    private func alive(_ values: [String: EffectValue], duration: Double, at time: Double) -> Int {
        let sprites = evaluator.evaluate(EffectNode(
            id: "s", type: EmitterEffect.descriptor.type, name: "s",
            startTime: 0, duration: duration, seed: 12, values: values,
        ))
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return states.count { $0.visible && $0.opacity > 0.01 }
    }

    @Test("the packs that hold things use clip-relative life")
    func thereIsSomethingToCheck() {
        let presets = Set(Self.clipLived.map(\.preset))
        for id in ["hud-loader", "hud-target-lock", "dandelion-sway", "god-rays", "sunbeam"] {
            #expect(presets.contains(id), "\(id) has nothing measured against its clip")
        }
    }

    /// Held for the whole clip means drawn at its very end, however long.
    @Test("a held emitter is still there at the end of a stretched clip",
          arguments: clipLived.filter { $0.emitter != "" })
    func heldSurvives(entry: (preset: String, emitter: String)) throws {
        let values = try values(entry.preset, entry.emitter)
        guard values[EmitterEffect.Param.lifeFraction] == .number(1),
              values[EmitterEffect.Param.emission] == .choice(EmitterEffect.Emission.burst.rawValue)
        else { return }
        let stretched = try duration(entry.preset) * 3
        #expect(alive(values, duration: stretched, at: stretched * 0.95) > 0,
                "\(entry.preset)/\(entry.emitter) is gone before the end of a stretched clip")
    }

    /// Cross-fading copies keep their overlap: as many alive mid-clip at
    /// three times the length as at the preset's own.
    @Test("cross-fading copies keep their overlap when stretched",
          arguments: clipLived.filter { $0.emitter != "" })
    func overlapSurvives(entry: (preset: String, emitter: String)) throws {
        let values = try values(entry.preset, entry.emitter)
        guard values[EmitterEffect.Param.emission] != .choice(EmitterEffect.Emission.burst.rawValue) else { return }
        let original = try duration(entry.preset)
        let before = alive(values, duration: original, at: original / 2)
        let after = alive(values, duration: original * 3, at: original * 1.5)
        #expect(abs(after - before) <= 1, "\(entry.preset)/\(entry.emitter): \(before) alive becomes \(after) stretched")
    }
}
