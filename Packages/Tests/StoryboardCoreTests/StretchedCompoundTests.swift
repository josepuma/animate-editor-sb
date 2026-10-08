import Foundation
import Testing

@testable import StoryboardCore

/// A compound stretched the way the editor stretches it: only the clip's own
/// duration changes, through `EffectDocument.resize`.
///
/// Reported as "life mode does nothing, it still cuts at the original ms".
/// Each layer keeps the duration it was placed with, and the evaluator reset a
/// layer's start but not its length — so every layer still believed the clip
/// was its old length. A whole-clip life was the old length; a continuous
/// layer stopped emitting part-way through. The tests that missed it
/// evaluated each layer on its own with a stretched duration typed in by
/// hand, which is not a clip the editor ever builds.
@Suite("Stretched compounds")
struct StretchedCompoundTests {
    private let evaluator = EffectEvaluator()

    /// Placed as `addPreset` places it — every layer given the preset's
    /// duration — then stretched by `resize`, which touches only the clip.
    private func stretched(_ id: String, by factor: Double) throws -> (EffectDocument, Double) {
        let preset = try #require(EmitterEffect.compoundPresets.first { $0.id == id })
        var document = EffectDocument()
        let placed = document.add(EmitterEffect.descriptor, at: 0, duration: preset.duration)
        var node = try #require(document[placed.id])
        node.values = preset.values
        node.layers = preset.layers.enumerated().map { index, layer in
            var child = EffectNode(
                id: "\(placed.id)/L\(index)", type: layer.effectType, name: layer.name,
                startTime: 0, duration: preset.duration,
                seed: EffectNode.layerSeed(from: node.seed, index: index), values: layer.values,
            )
            if case let .number(x) = layer.values[EmitterEffect.Param.x] { child.transform[value: .x] = x }
            if case let .number(y) = layer.values[EmitterEffect.Param.y] { child.transform[value: .y] = y }
            return child
        }
        document[placed.id] = node
        let longer = preset.duration * factor
        document.resize(placed.id, startTime: 0, duration: longer)
        return (document, longer)
    }

    private func alive(_ document: EffectDocument, at time: Double, layer name: String) throws -> Int {
        let node = try #require(document.nodes.first)
        let index = try #require(node.layers.firstIndex { $0.name == name })
        let prefix = "\(node.id)/L\(index)/"
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(evaluator.evaluate(document)), at: time, into: &states)
        return states.count { $0.spriteId.hasPrefix(prefix) && $0.visible && $0.opacity > 0.01 }
    }

    /// The report itself: a held ring of a stretched loader, at the end.
    @Test("a held layer lasts a stretched clip", arguments: [
        ("hud-loader", "Segments"), ("hud-target-lock", "Bracket Top"), ("dandelion-sway", "Middle"),
    ])
    func heldLayerLasts(id: String, layer: String) throws {
        let (document, length) = try stretched(id, by: 3)
        #expect(try alive(document, at: length * 0.95, layer: layer) > 0,
                "\(id)/\(layer) is gone before the end of a clip stretched to \(Int(length))ms")
    }

    /// And the older half of the same bug: a continuous layer kept emitting
    /// only over the clip's old length.
    @Test("a continuous layer keeps emitting across a stretched clip", arguments: [
        ("hud-loader", "Current"), ("fire-ring", "Column"), ("sunbeam", "Body"),
    ])
    func continuousLayerKeepsEmitting(id: String, layer: String) throws {
        let (document, length) = try stretched(id, by: 3)
        #expect(try alive(document, at: length * 0.8, layer: layer) > 0,
                "\(id)/\(layer) stops emitting in a clip stretched to \(Int(length))ms")
    }
}
