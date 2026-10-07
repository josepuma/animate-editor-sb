import Foundation
import Testing

@testable import StoryboardCore

/// The Text FX pack: titles with a look, a scene, or particles of their own.
///
/// Every preset is placed as the editor places it (`PlacedPreset`), so a
/// layer that draws nothing or a filter that never arrives shows up here
/// rather than in somebody's storyboard.
@Suite("Text FX presets")
struct TextFXPresetTests {
    private static let ids = [
        "neon-sign", "rgb-split", "ghost-trail", "focus-in", "drop-shadow-pop",
        "impact-title", "fire-title", "cosmic-intro", "lyric-sparkle", "warp-title",
        "spark-landing", "dust-drop", "comet-trail", "disintegrate", "ember-type",
    ]

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(TextEffect.presets.first { $0.id == id })
    }

    @Test("all fifteen are in the library, last, in their own pack")
    func inTheLibrary() {
        let ids = TextEffect.presets.map(\.id)
        #expect(Array(ids.suffix(Self.ids.count)) == Self.ids)
        #expect(TextEffect.fxPresets.allSatisfy { $0.pack == TextEffect.fxPack })
    }

    @Test("each brings something besides the letters", arguments: ids)
    func bringsSomething(id: String) throws {
        let preset = try preset(id)
        let particles = preset.values[TextGlyphParticles.Param.mode] != .choice("None")
        #expect(!preset.filters.isEmpty || !preset.layers.isEmpty || particles)
    }

    /// `emitterLayer` falls back to no values for an id it cannot find — a
    /// layer of the emitter's bare defaults, silently. Every layer has to
    /// draw, and draw more than one sprite.
    @Test("every layer of a compound draws", arguments: ids)
    func layersDraw(id: String) throws {
        let preset = try preset(id)
        guard !preset.layers.isEmpty else { return }
        let node = PlacedPreset.node(preset)
        let drawn = EffectEvaluator().evaluate(node)
        for (index, layer) in preset.layers.enumerated() {
            let own = drawn.filter { $0.id.hasPrefix("\(node.id)/L\(index)/") }
            #expect(!own.isEmpty, "\(id) / \(layer.name)")
            #expect(layer.values.count > 3, "\(id) / \(layer.name) reads no preset")
        }
    }

    /// A layer that waits is waiting for the letters: nothing it draws may
    /// start before its delay.
    @Test("a waiting layer starts no earlier than its delay", arguments: ids)
    func layersWait(id: String) throws {
        let preset = try preset(id)
        let node = PlacedPreset.node(preset)
        let drawn = EffectEvaluator().evaluate(node)
        for (index, layer) in preset.layers.enumerated() where layer.delay > 0 {
            let starts = drawn
                .filter { $0.id.hasPrefix("\(node.id)/L\(index)/") }
                .flatMap(\.commands).filter { $0.kind != .parameter }.map(\.startTime)
            #expect((starts.min() ?? 0) >= layer.delay - 1, "\(id) / \(layer.name)")
        }
    }

    /// The impact is the letters arriving: its layers wait exactly for the
    /// slam to finish, not for it to start.
    @Test("the impact lands with the title")
    func impactOnLanding() throws {
        let preset = try preset("impact-title")
        guard case let .number(fadeIn) = preset.values[TextEffect.Param.fadeIn] else {
            Issue.record("no fade-in"); return
        }
        #expect(preset.layers.allSatisfy { $0.delay == fadeIn })
    }

    @Test("a filter preset arrives with its filter", arguments: ids)
    func filtersArrive(id: String) throws {
        let preset = try preset(id)
        let node = PlacedPreset.node(preset)
        #expect(node.filters.map(\.type) == preset.filters.map(\.type))
    }

    @Test("focus-in starts blurred and ends sharp")
    func focusRacks() throws {
        let node = PlacedPreset.node(try preset("focus-in"))
        let blur = try #require(node.filters.first { $0.type == BlurFilter.descriptor.type })
        let radius = try #require(blur.animations[BlurFilter.Param.radius])
        #expect((radius.keyframes.first?.value ?? 0) > 8)
        #expect(radius.keyframes.last?.value == 0)
        // And what is drawn changes image as it racks: more than one blur level.
        let paths = Set(EffectEvaluator().evaluate(node).map(\.filePath))
        #expect(paths.filter { $0.hasPrefix("__derived__/blur") }.count > 2)
    }

    @Test("particle presets throw particles", arguments: ["spark-landing", "dust-drop", "comet-trail", "disintegrate", "ember-type"])
    func particlesThrown(id: String) throws {
        let drawn = PlacedPreset.sprites(try preset(id), text: "HELLO")
        #expect(drawn.contains { $0.id.contains("/p") })
    }
}
