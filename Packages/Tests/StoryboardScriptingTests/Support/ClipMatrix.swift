import Foundation
import StoryboardCore
import StoryboardScripting
import StoryboardTestSupport

/// One clip of every kind the editor places, for tests that must hold for a
/// filter whatever it is applied to.
///
/// A filter sees only finished sprites, so in principle it cannot tell an
/// emitter from a script. In practice each kind writes a different shape of
/// command list — an emitter splits a curved path into chords, a script writes
/// whatever the author typed, text staggers fades, a compound evaluates its
/// layers with their own delays — and a filter tested on one sprite is tested
/// on none of those. Lives with the scripting tests because it is the only
/// target that can reach the real `ScriptEngine` without Core's tests
/// depending on it.
enum ClipMatrix {
    struct Clip: CustomStringConvertible, Sendable {
        let name: String
        let node: EffectNode
        var description: String { name }
    }

    /// Short and small on purpose: every filter runs against every clip,
    /// twice, so each clip has to cost milliseconds, not the hundreds a full
    /// preset does.
    static let duration: Double = 2000

    static let clips: [Clip] = [emitter, script, text, shape, compound]

    /// The real runtime, and a tempo for anything that listens for one.
    /// Built per call: the evaluator is a value, and sharing one across
    /// parallel tests would share nothing mutable anyway.
    static var evaluator: EffectEvaluator {
        var evaluator = EffectEvaluator(scriptRuntime: { ScriptEngine().run($0) })
        evaluator.beat = BeatGrid(timing: BeatmapTimingData(uninheritedPoints: [
            UninheritedTimingPoint(time: 0, beatLength: 500, meter: 4, kiai: false),
        ]))
        return evaluator
    }

    /// The clip with only `filter` on it, evaluated as the editor would.
    static func evaluate(_ clip: Clip, with filter: FilterNode? = nil) -> [StoryboardSprite] {
        var node = clip.node
        node.filters = filter.map { [$0] } ?? []
        return evaluator.evaluate(node)
    }

    /// A filter node as `addFilter` makes one: every default underneath, then
    /// whatever the test overrides.
    static func filterNode(
        _ descriptor: FilterDescriptor,
        values: [String: EffectValue] = [:],
    ) -> FilterNode {
        FilterNode(
            id: "matrix-\(descriptor.type)",
            type: descriptor.type,
            values: descriptor.defaultValues.merging(values) { _, new in new },
        )
    }

    /// The same filter with its numbers turned up, so a guard sees what the
    /// filter writes when it is doing something.
    static func exercised(_ descriptor: FilterDescriptor) -> FilterNode {
        filterNode(descriptor, values: FilterExercise.exercised(descriptor))
    }

    /// What the clip draws, in a form two evaluations of the SAME node can be
    /// compared by. Never across two placements: sprite ids carry the node id.
    static func signature(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.map(String.init(reflecting:))
    }

    // MARK: - The clips

    /// Gravity, so every particle's path is several chords rather than one.
    private static let emitter: Clip = {
        var node = PlacedPreset.node(EmitterEffect.fountain)
        node.duration = duration
        node.values[EmitterEffect.Param.count] = .integer(24)
        return Clip(name: "emitter", node: node)
    }()

    /// The real bridge: moves, fades, scales and turns, the four families a
    /// filter is most likely to rewrite.
    private static let script: Clip = {
        var document = EffectDocument()
        var node = document.add(ScriptEffect.descriptor, at: 0, duration: duration)
        node.scriptSource = """
        for (let i = 0; i < 12; i++) {
          const born = i * 60
          sprite(Image.soft)
            .move(Ease.quadOut, born, born + 900, 320, 240, 320 + i * 20, 240 - i * 10)
            .fade(born, born + 150, 0, 1)
            .scale(born, born + 900, 0.5, 1)
            .rotate(born, born + 900, 0, 1)
        }
        """
        return Clip(name: "script", node: node)
    }()

    /// A preset that drops letters in, so the glyphs move as well as fade.
    private static let text: Clip = {
        var node = PlacedPreset.node(TextEffect.drop, text: "Matrix")
        node.duration = duration
        return Clip(name: "text", node: node)
    }()

    /// A clip animated by keyframes rather than by its effect: the transform
    /// writes the movement, which is a different path into the commands.
    private static let shape: Clip = {
        var document = EffectDocument()
        var node = document.add(ShapeEffect.descriptor, at: 0, duration: duration)
        var track = node.transform[.x]
        _ = track.set(220, at: 0)
        _ = track.set(420, at: duration, easing: .quadOut)
        node.transform[.x] = track
        return Clip(name: "shape", node: node)
    }()

    /// Several emitters wearing one name, one of them waiting: a filter has to
    /// handle layers evaluated with their own transforms and a late start.
    private static let compound: Clip = {
        var node = PlacedPreset.node(EmitterEffect.firework)
        node.duration = duration
        node.values[EmitterEffect.Param.count] = .integer(16)
        for index in node.layers.indices {
            node.layers[index].duration = duration
            node.layers[index].values[EmitterEffect.Param.count] = .integer(16)
        }
        node.layers[node.layers.count - 1].delay = 300
        return Clip(name: "compound", node: node)
    }()
}
