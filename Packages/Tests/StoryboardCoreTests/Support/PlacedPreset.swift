import Foundation

@testable import StoryboardCore

/// A preset placed the way the editor's `addPreset` places it: values, then
/// its layers as child nodes — positions on the transform, a seed each, and
/// their delay — then its filters.
///
/// A test that evaluates only the parent's values measures something the
/// editor never builds: a compound would lose its layers, a filter preset its
/// look, and two presets apart only in those would compare equal.
enum PlacedPreset {
    static func node(_ preset: EffectPreset, text: String? = nil, at start: Double = 0) -> EffectNode {
        let library = EffectLibrary.standard
        var document = EffectDocument()
        guard let descriptor = library.descriptor(for: preset.effectType) else {
            return document.add(TextEffect.descriptor, at: start, duration: preset.duration)
        }
        var node = document.add(descriptor, at: start, duration: preset.duration)
        node.values = preset.values
        if let text { node.values[TextEffect.Param.text] = .text(text) }
        if case let .number(x) = preset.values[EmitterEffect.Param.x] { node.transform[value: .x] = x }
        if case let .number(y) = preset.values[EmitterEffect.Param.y] { node.transform[value: .y] = y }

        node.layers = preset.layers.enumerated().compactMap { index, layer in
            guard let layerDescriptor = library.descriptor(for: layer.effectType) else { return nil }
            var child = EffectNode(
                id: "\(node.id)/L\(index)",
                type: layer.effectType,
                name: layer.name,
                layer: node.layer,
                startTime: 0,
                duration: preset.duration,
                seed: EffectNode.layerSeed(from: node.seed, index: index),
                values: layerDescriptor.defaultValues.merging(layer.values) { _, new in new },
                delay: layer.delay > 0 ? layer.delay : nil,
            )
            if case let .number(x) = layer.values[EmitterEffect.Param.x] { child.transform[value: .x] = x }
            if case let .number(y) = layer.values[EmitterEffect.Param.y] { child.transform[value: .y] = y }
            return child
        }
        node.filters = preset.filterNodes(using: .standard) { "\(node.id)-f\($0)" }
        return node
    }

    static func sprites(_ preset: EffectPreset, text: String? = nil) -> [StoryboardSprite] {
        EffectEvaluator().evaluate(node(preset, text: text))
    }
}
