import Testing

@testable import StoryboardCore

@Suite("Text presets")
struct TextPresetTests {
    private func sprites(_ preset: EffectPreset) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: preset.duration)
        for (key, value) in preset.values { node.values[key] = value }
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    /// All of them are the one effect with different numbers — no special cases
    /// in the evaluator, which is what keeps the library honest.
    @Test("every preset belongs to the text effect", arguments: TextEffect.presets)
    func presetsAreTextEffects(preset: EffectPreset) {
        #expect(preset.effectType == TextEffect.descriptor.type)
    }

    @Test("every preset draws something", arguments: TextEffect.presets)
    func presetsDraw(preset: EffectPreset) {
        #expect(!sprites(preset).isEmpty)
    }

    /// A preset that is invisible halfway through its own block reads as
    /// broken, whatever its numbers say. The emitter library had exactly this
    /// bug, found by exactly this test.
    @Test("every preset is visible partway through", arguments: TextEffect.presets)
    func presetsAreVisibleMidway(preset: EffectPreset) {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites(preset)),
            at: preset.duration * 0.5,
            into: &states,
        )

        #expect(states.contains { $0.visible && $0.opacity > 0.01 })
    }

    @Test("presets have distinct names and ids")
    func namesAreUnique() {
        #expect(Set(TextEffect.presets.map(\.id)).count == TextEffect.presets.count)
        #expect(Set(TextEffect.presets.map(\.name)).count == TextEffect.presets.count)
    }

    /// Twelve presets that all animate the same way would be one preset listed
    /// twelve times.
    @Test("presets differ from one another")
    func presetsDiffer() {
        let signatures = TextEffect.presets.map { preset in
            [
                preset.values[TextEffect.Param.stagger],
                preset.values[TextEffect.Param.easing],
                preset.values[TextEffect.Param.riseFrom],
                preset.values[TextEffect.Param.driftFrom],
                preset.values[TextEffect.Param.scaleFrom],
                preset.values[TextEffect.Param.staggerFrom],
            ]
        }

        #expect(Set(signatures.map(String.init(describing:))).count == signatures.count)
    }
}
