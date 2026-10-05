import Foundation
import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// Tallies which lanes the camera was baked into, by the clips riding on them.
private final class BakeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func record(_ sprites: [StoryboardSprite]) {
        lock.lock()
        defer { lock.unlock() }
        for id in Set(sprites.map(\.id)) { counts[id, default: 0] += 1 }
    }

    func count(_ id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[id] ?? 0
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        counts.removeAll()
    }
}

/// One sprite per clip, faded across the clip, named after the clip.
private struct PlainEffect: Effect {
    static let descriptor = EffectDescriptor(
        type: "plain",
        name: "Plain",
        category: .generate,
        systemImage: "square",
        parameters: [],
    )

    func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        var sprite = StoryboardSprite(
            id: context.node.id,
            layer: .foreground,
            origin: .centre,
            filePath: "plain.png",
            defaultX: 320,
            defaultY: 240,
        )
        sprite.commands = [
            Command(easing: .linear, startTime: 0, endTime: context.duration, payload: .fade(start: 1, end: 1)),
        ]
        return [sprite]
    }
}

/// The camera is re-baked only into lanes whose inputs moved.
///
/// Measured on a real project (38 clips, a rotation-keyed camera, 4,240
/// sprites): stretching one shape cost 0.9ms of evaluation and **4,120ms** of
/// baking the camera into every lane again — 3,286ms of it into a script lane
/// the edit never touched.
@Suite("Camera lane cache")
struct CameraLaneCacheTests {
    private let evaluator = EffectEvaluator(library: EffectLibrary(effects: [PlainEffect()]))

    private func cache(_ counter: BakeCounter) -> EvaluationCache {
        EvaluationCache { camera, lane, z, follows in
            counter.record(lane)
            return CameraTransform.apply(camera, to: lane, z: z, followsCamera: follows)
        }
    }

    private func node(_ id: String, duration: Double = 1000) -> EffectNode {
        EffectNode(id: id, type: "plain", name: id, startTime: 0, duration: duration)
    }

    /// Two lanes of one clip each, under a camera that pans and rolls.
    private func document() -> EffectDocument {
        var camera = StoryboardCamera()
        camera[.x] = KeyframeTrack([Keyframe(time: 0, value: 320), Keyframe(time: 1000, value: 400)])
        camera[.rotation] = KeyframeTrack([Keyframe(time: 0, value: 0), Keyframe(time: 1000, value: 30)])
        return EffectDocument(
            tracks: [
                EffectTrack(id: "A", name: "A", nodes: [node("a")]),
                EffectTrack(id: "B", name: "B", nodes: [node("b")], z: 300),
            ],
            camera: camera,
        )
    }

    /// Sprites carry no `Equatable`; their full reflection compares every
    /// field, commands included, which is what "the same output" means here.
    private func same(_ lhs: [StoryboardSprite], _ rhs: [StoryboardSprite]) -> Bool {
        String(reflecting: lhs) == String(reflecting: rhs)
    }

    /// The uncached answer: every lane stamped with its layer and baked.
    private func fresh(_ document: EffectDocument) -> [StoryboardSprite] {
        document.tracks.flatMap { track -> [StoryboardSprite] in
            guard track.isVisible else { return [] }
            let lane = track.nodes.flatMap(evaluator.evaluate).map { sprite in
                var placed = sprite
                placed.layer = track.layer
                return placed
            }
            return CameraTransform.apply(document.camera, to: lane, z: track.z, followsCamera: track.followsCamera)
        }
    }

    @Test("editing a clip re-bakes only its own lane")
    func editRebakesOnlyItsLane() {
        let counter = BakeCounter()
        let cache = cache(counter)
        var document = document()
        _ = cache.sprites(for: document, using: evaluator)
        counter.reset()

        document.tracks[0].nodes[0].duration = 2000
        cache.invalidate(node: "a")
        let sprites = cache.sprites(for: document, using: evaluator)

        #expect(counter.count("a") == 1)
        #expect(counter.count("b") == 0, "lane B did not change and must not be baked again")
        #expect(same(sprites, fresh(document)))
    }

    @Test("a pass with nothing changed bakes nothing")
    func unchangedPassBakesNothing() {
        let counter = BakeCounter()
        let cache = cache(counter)
        let document = document()
        let first = cache.sprites(for: document, using: evaluator)
        counter.reset()

        let second = cache.sprites(for: document, using: evaluator)

        #expect(counter.count("a") == 0)
        #expect(counter.count("b") == 0)
        #expect(same(second, first))
    }

    @Test("moving the camera re-bakes every lane that follows it")
    func cameraEditRebakesAll() {
        let counter = BakeCounter()
        let cache = cache(counter)
        var document = document()
        _ = cache.sprites(for: document, using: evaluator)
        counter.reset()

        document.camera[.x] = KeyframeTrack([Keyframe(time: 0, value: 320), Keyframe(time: 1000, value: 500)])
        let sprites = cache.sprites(for: document, using: evaluator)

        #expect(counter.count("a") == 1)
        #expect(counter.count("b") == 1)
        #expect(same(sprites, fresh(document)))
    }

    /// Every lane property the bake or the layer stamp reads has to be part of
    /// the key — each one, changed alone, must reach the output.
    @Test(
        "a lane property the bake reads re-bakes that lane",
        arguments: ["z", "followsCamera", "layer", "order"],
    )
    func laneChangeRebakes(_ property: String) {
        let counter = BakeCounter()
        let cache = cache(counter)
        var document = document()
        document.tracks[0].nodes.append(node("a2", duration: 500))
        _ = cache.sprites(for: document, using: evaluator)
        counter.reset()

        switch property {
        case "z": document.tracks[0].z = 800
        case "followsCamera": document.tracks[0].followsCamera = false
        case "layer": document.tracks[0].layer = .background
        default: document.tracks[0].nodes.reverse()
        }
        let sprites = cache.sprites(for: document, using: evaluator)

        #expect(same(sprites, fresh(document)), "stale bake served after changing \(property)")
        #expect(counter.count("b") == 0)
    }

    @Test("an edit that names no clip re-bakes every lane")
    func unnamedInvalidationRebakesAll() {
        let counter = BakeCounter()
        let cache = cache(counter)
        let document = document()
        _ = cache.sprites(for: document, using: evaluator)
        counter.reset()

        cache.invalidate(node: nil)
        _ = cache.sprites(for: document, using: evaluator)

        #expect(counter.count("a") == 1)
        #expect(counter.count("b") == 1)
    }

    @Test("hiding and showing a lane serves its bake again")
    func hiddenLaneKeepsItsBake() {
        let counter = BakeCounter()
        let cache = cache(counter)
        var document = document()
        let shown = cache.sprites(for: document, using: evaluator)

        document.tracks[1].isVisible = false
        let hidden = cache.sprites(for: document, using: evaluator)
        #expect(!hidden.contains { $0.id == "b" })

        counter.reset()
        document.tracks[1].isVisible = true
        let again = cache.sprites(for: document, using: evaluator)

        #expect(counter.count("b") == 0)
        #expect(same(again, shown))
    }

    @Test("the world view, without the camera, is untouched by the lane cache")
    func worldIgnoresBake() {
        let counter = BakeCounter()
        let cache = cache(counter)
        let document = document()
        _ = cache.sprites(for: document, using: evaluator)
        counter.reset()

        let world = cache.sprites(for: document, using: evaluator, applyingCamera: false)

        #expect(counter.count("a") == 0)
        #expect(world.map(\.id) == ["a", "b"])
        #expect(!same(world, fresh(document)), "the world view must not carry the camera")
    }
}
