import Foundation
import Testing

@testable import StoryboardCore

/// Beat Pulse beats each sprite only while that sprite is alive.
///
/// Reported as filters "colliding": a text clip with Spark Trail then Beat
/// Pulse drew huge white blobs along the path. Pulse worked out its beats over
/// the whole clip and wrote them on every sprite, so a spark born at second 3
/// got beats from second 0 — alive before it was born, and drawn there with
/// its first command's opening values: full opacity and `1 + punch` scale on a
/// 64px or 512px texture instead of the 0.125 it was given.
@Suite("Beat pulse respects each sprite's life")
struct PulseLifeTests {
    private let beat = BeatGrid(timing: BeatmapTimingData(uninheritedPoints: [
        UninheritedTimingPoint(time: 0, beatLength: 500, meter: 4, kiai: false),
    ]))

    private func pulse(_ sprites: [StoryboardSprite]) -> [StoryboardSprite] {
        let node = FilterNode(id: "p", type: "pulse", values: PulseFilter.descriptor.defaultValues.merging([
            PulseFilter.Param.release: .number(0.5),
        ]) { _, new in new })
        return PulseFilter().apply(to: sprites, in: FilterContext(descriptor: PulseFilter.descriptor, node: node, beat: beat))
    }

    private func sprite(_ id: String, from start: Double, to end: Double) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: "a.png", defaultX: 320, defaultY: 240,
            commands: [
                Command(easing: .quadIn, startTime: start, endTime: end, payload: .fade(start: 1, end: 0)),
                Command(easing: .linear, startTime: start, endTime: end, payload: .scale(start: 0.125, end: 0.04)),
            ],
        )
    }

    private func life(_ sprite: StoryboardSprite) -> (start: Double, end: Double) {
        let prepared = StoryboardResolver.prepare([sprite])[0]
        return (prepared.activeStart, prepared.activeEnd)
    }

    @Test("a short-lived sprite in a long clip keeps its own life")
    func keepsLife() {
        let out = pulse([sprite("line", from: 0, to: 6000), sprite("spark", from: 3000, to: 3600)])
        let spark = life(out[1])
        #expect(spark.start >= 3000, "alive from \(spark.start)")
        #expect(spark.end <= 3600, "alive until \(spark.end)")
    }

    @Test("it still beats while it is alive, from its own size")
    func stillBeats() {
        let out = pulse([sprite("line", from: 0, to: 6000), sprite("spark", from: 3000, to: 3600)])
        let scales = out[1].commands.compactMap { command -> Double? in
            if case let .scale(start, _) = command.payload { start } else { nil }
        }
        #expect(scales.count > 1, "a beat at 3000 and 3500")
        #expect(scales.allSatisfy { $0 < 0.5 }, "never drawn at full texture size: \(scales)")
    }

    /// The case as reported, end to end through the filters' own order.
    @Test("Spark Trail then Beat Pulse on text draws no blobs")
    func sparkTrailThenPulse() {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 4000)
        node.values[TextEffect.Param.text] = .text("Hi")
        var move = node.transform[.x]
        _ = move.set(120, at: 0)
        _ = move.set(520, at: 4000)
        node.transform[.x] = move
        node.filters = [
            FilterNode(id: "t", type: SparkTrailFilter.descriptor.type, values: SparkTrailFilter.descriptor.defaultValues),
            FilterNode(id: "p", type: PulseFilter.descriptor.type, values: PulseFilter.descriptor.defaultValues),
        ]
        var evaluator = EffectEvaluator()
        evaluator.beat = beat
        let sprites = evaluator.evaluate(node)
        let sparks = sprites.filter { $0.id.contains("/t") }
        #expect(!sparks.isEmpty)
        for spark in sparks {
            let born = spark.commands.filter { $0.kind == .move }.map(\.startTime).min()!
            #expect(life(spark).start >= born - 1e-6, "\(spark.id) alive before it is thrown")
        }
    }
}
