import Foundation
import Testing

@testable import StoryboardCore

/// A compound layer that waits inside its clip before it starts.
///
/// Read from the evaluated sprites: when a layer's commands begin and end is
/// the whole of what a delay promises.
@Suite("Layer delay")
struct LayerDelayTests {
    private let evaluator = EffectEvaluator()

    /// A shape holds for its whole clip, so its commands span exactly the
    /// time the layer is alive.
    private func shape(id: String, delay: Double? = nil) -> EffectNode {
        EffectNode(
            id: id, type: ShapeEffect.descriptor.type, name: "Shape",
            startTime: 0, duration: 1000,
            values: ShapeEffect.descriptor.defaultValues,
            delay: delay,
        )
    }

    private func clip(layerDelay: Double?, start: Double = 500, duration: Double = 3000) -> EffectNode {
        var parent = shape(id: "parent")
        parent.startTime = start
        parent.duration = duration
        parent.layers = [shape(id: "parent/L0", delay: layerDelay)]
        return parent
    }

    private func span(of layer: [StoryboardSprite]) -> (start: Double, end: Double) {
        let commands = layer.flatMap(\.commands).filter { $0.kind != .parameter }
        return (commands.map(\.startTime).min() ?? .nan, commands.map(\.endTime).max() ?? .nan)
    }

    private func layerSprites(_ node: EffectNode) -> [StoryboardSprite] {
        evaluator.evaluate(node).filter { $0.id.hasPrefix("parent/L0") }
    }

    @Test("no delay: the layer runs the whole clip, as it always has")
    func noDelay() {
        let layer = span(of: layerSprites(clip(layerDelay: nil)))
        #expect(layer.start == 500)
        #expect(layer.end == 3500)
    }

    @Test("a delayed layer starts that much into the clip and still ends with it")
    func delayed() {
        let layer = span(of: layerSprites(clip(layerDelay: 800)))
        #expect(layer.start == 1300)
        #expect(layer.end == 3500)
    }

    @Test("a delay past the clip leaves the layer nothing to draw")
    func pastTheEnd() {
        #expect(layerSprites(clip(layerDelay: 9000)).allSatisfy { $0.commands.isEmpty })
    }

    @Test("stretching the clip keeps the wait and moves the end")
    func stretched() {
        let layer = span(of: layerSprites(clip(layerDelay: 800, duration: 6000)))
        #expect(layer.start == 1300)
        #expect(layer.end == 6500)
    }

    @Test("an unset delay is not written, so saved projects keep their bytes")
    func notWritten() throws {
        let data = try JSONEncoder().encode(shape(id: "a"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"delay\""))

        let delayed = try JSONEncoder().encode(shape(id: "a", delay: 250))
        let decoded = try JSONDecoder().decode(EffectNode.self, from: delayed)
        #expect(decoded.delay == 250)
    }

    // ─── Presets ─────────────────────────────────────────────────────────────

    @Test("a preset's filter keyframes reach the placed filter, with fresh ids")
    func presetFilterAnimations() throws {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: 20),
            Keyframe(time: 600, value: 0, easing: .quadOut),
        ])
        let preset = EffectPreset(
            id: "p", name: "P", effectType: TextEffect.descriptor.type, summary: "",
            values: TextEffect.descriptor.defaultValues,
            filters: [EffectPreset.Filter(type: BlurFilter.descriptor.type, animations: [BlurFilter.Param.radius: track])],
        )
        let first = preset.filterNodes(using: .standard) { "f\($0)" }
        let second = preset.filterNodes(using: .standard) { "g\($0)" }
        let placed = try #require(first.first?.animations[BlurFilter.Param.radius])
        #expect(placed.keyframes.map(\.time) == [0, 600])
        #expect(placed.keyframes.map(\.value) == [20, 0])
        #expect(placed.keyframes.map(\.easing) == [.linear, .quadOut])
        let other = try #require(second.first?.animations[BlurFilter.Param.radius])
        #expect(Set(placed.keyframes.map(\.id)).isDisjoint(with: other.keyframes.map(\.id)))
    }
}
