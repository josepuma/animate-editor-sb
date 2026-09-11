import Foundation
import Testing

@testable import StoryboardCore

/// Swapping a clip's preset without losing what the clip is.
///
/// A preset stores **every** value its effect has, because it is built as
/// `defaultValues.merging(…)`. Applied whole to a placed clip that would take
/// the author's text, font, colour and size back to the defaults — so trying a
/// second movement meant rebuilding the clip, which is the work presets exist
/// to remove.
///
/// So a preset also carries what it actually changed. Derived rather than
/// listed: a set of "content" keys kept by hand is a list to maintain, and
/// forgetting an entry there does not fail — it silently discards work. That
/// shape has cost this project five separate bugs.
@Suite("Preset overrides")
struct PresetOverridesTests {
    /// The overrides are the preset's own values, not the whole effect.
    @Test("a preset knows what it changed")
    func presetKnowsItsOverrides() throws {
        let typewriter = try #require(TextEffect.presets.first { $0.id == "typewriter" })

        #expect(
            typewriter.overrides.count < typewriter.values.count,
            "the diff has to be smaller than the full set, or it is not a diff",
        )
        #expect(!typewriter.overrides.isEmpty, "and it has to say something")
        #expect(
            typewriter.overrides.keys.allSatisfy { typewriter.values[$0] != nil },
            "every override is one of its values",
        )
    }

    /// Every preset of every effect carries one.
    ///
    /// Parameterised because the four construction sites are separate helpers,
    /// and one of them forgetting is a preset that silently swaps to nothing.
    @Test("every preset carries its overrides", arguments: allPresets())
    func everyPresetCarriesOverrides(_ preset: EffectPreset) {
        #expect(!preset.overrides.isEmpty, "\(preset.id) changes nothing from its defaults")
    }

    /// Swapping keeps the text and takes the movement.
    @Test("swapping a preset keeps the clip's content")
    func swappingKeepsContent() throws {
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        var node = document.add(TextEffect.descriptor, at: 0, duration: 4000, on: track.id)

        // What the author set, which a swap must not touch.
        node.values[TextEffect.Param.text] = .text("hello")
        node.values[TextEffect.Param.size] = .number(72)
        document[node.id] = node

        let drop = try #require(TextEffect.presets.first { $0.id == "drop" })
        document.applyPreset(drop, to: node.id, siblings: TextEffect.presets)

        let after = try #require(document[node.id])
        #expect(after.values[TextEffect.Param.text] == .text("hello"), "the words stay")
        #expect(after.values[TextEffect.Param.size] == .number(72), "and so does the size")
        for (key, value) in drop.overrides {
            #expect(after.values[key] == value, "\(key) has to come from the preset")
        }
    }

    /// A second swap replaces the first one's movement rather than layering.
    ///
    /// The case that made this worth building: trying presets one after
    /// another. Left additive, a value the first preset set and the second does
    /// not name would survive — so the clip would be a mixture of two
    /// movements and neither would read as itself.
    @Test("swapping twice lands on the second preset, not a blend")
    func swappingTwiceIsNotABlend() throws {
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        let node = document.add(TextEffect.descriptor, at: 0, duration: 4000, on: track.id)

        let scatter = try #require(TextEffect.presets.first { $0.id == "scatter" })
        let typewriter = try #require(TextEffect.presets.first { $0.id == "typewriter" })

        document.applyPreset(scatter, to: node.id, siblings: TextEffect.presets)
        document.applyPreset(typewriter, to: node.id, siblings: TextEffect.presets)

        let after = try #require(document[node.id])
        // Anything scatter set and typewriter does not name goes back to the
        // default rather than lingering.
        for key in scatter.overrides.keys where typewriter.overrides[key] == nil {
            #expect(
                after.values[key] == TextEffect.descriptor.defaultValues[key],
                "\(key) is left over from the first preset",
            )
        }
        #expect(
            after.values[TextEffect.Param.stagger] == typewriter.overrides[TextEffect.Param.stagger],
        )
    }

    /// A preset for another effect is refused.
    @Test("a preset for a different effect does nothing")
    func wrongEffectIsRefused() throws {
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        let node = document.add(TextEffect.descriptor, at: 0, duration: 4000, on: track.id)
        let before = try #require(document[node.id]).values

        let emitter = try #require(EmitterEffect.presets.first)
        document.applyPreset(emitter, to: node.id, siblings: EmitterEffect.presets)

        #expect(try #require(document[node.id]).values == before)
    }

    // MARK: -

    static func allPresets() -> [EffectPreset] {
        TextEffect.presets + EmitterEffect.presets
            + EmitterEffect.compoundPresets + ShapeEffect.presets
    }
}
