import Foundation
import Testing

@testable import StoryboardCore

/// The Dandelion pack: seeds on the wind and heads swaying in it.
///
/// Measured from the sprites, through the same placement the editor does:
/// that seeds go downwind, that a flower leans about its stem instead of
/// sliding, and that a blown head stays in one piece while its seeds leave it.
@Suite("Dandelion presets")
struct DandelionPresetTests {
    private let evaluator = EffectEvaluator()

    private static let all = ["seed-drift", "seed-gust", "dandelion-sway", "dandelion-blow"]

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(
            (EmitterEffect.presets + EmitterEffect.compoundPresets).first { $0.id == id },
            "no preset \(id)",
        )
    }

    private func placed(_ values: [String: EffectValue], id: String, duration: Double, seed: UInt64 = 12) -> EffectNode {
        var node = EffectNode(
            id: id, type: EmitterEffect.descriptor.type, name: id,
            startTime: 0, duration: duration, seed: seed, values: values,
        )
        if case let .number(x) = values[EmitterEffect.Param.x] { node.transform[value: .x] = x }
        if case let .number(y) = values[EmitterEffect.Param.y] { node.transform[value: .y] = y }
        return node
    }

    /// The whole clip as `EditorShellModel.addPreset` builds it — parent,
    /// layers and filters. Anything less is a clip the app never draws.
    private func clip(_ preset: EffectPreset) -> EffectNode {
        var node = placed(preset.values, id: preset.id, duration: preset.duration)
        node.layers = preset.layers.enumerated().map { index, layer in
            placed(layer.values, id: "\(preset.id)/L\(index)", duration: preset.duration,
                   seed: EffectNode.layerSeed(from: 12, index: index))
        }
        node.filters = preset.filterNodes(using: .standard) { "\(preset.id)-f\($0)" }
        return node
    }

    private func layerID(_ preset: EffectPreset, _ name: String) throws -> String {
        let index = try #require(preset.layers.firstIndex { $0.name == name }, "no layer \(name)")
        return "\(preset.id)/L\(index)/"
    }

    private func states(of node: EffectNode, at time: Double) -> [SpriteRenderState] {
        let prepared = StoryboardResolver.prepare(evaluator.evaluate(node))
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: time, into: &states)
        return states.filter { $0.visible && $0.opacity > 0.01 }
    }

    @Test("every dandelion preset is in its pack, painted and drawn with the pack's textures", arguments: all)
    func packAndTextures(id: String) throws {
        let preset = try preset(id)
        #expect(preset.pack == "Dandelion")
        let drawing = ([preset.values] + preset.layers.map(\.values))
            .filter { $0[EmitterEffect.Param.opacity] != .number(0) }
        try #require(!drawing.isEmpty)
        for values in drawing {
            guard case let .text(path) = values[EmitterEffect.Param.sprite] else {
                Issue.record("\(id) has an emitter with no sprite")
                continue
            }
            #expect(path.contains("dandelion_"), "\(id) draws \(path)")
            // A seed blocks light; additive would make the fluff glow.
            #expect(values[EmitterEffect.Param.additive] == .toggle(false), "\(id) is additive")
        }
    }

    /// One wind for the whole pack. A seed blowing the other way over a
    /// meadow leaning this way is two weathers at once.
    @Test("seeds travel downwind", arguments: [
        ("seed-drift", nil), ("seed-gust", nil), ("dandelion-blow", "Seeds"),
    ] as [(String, String?)])
    func seedsGoDownwind(id: String, layer: String?) throws {
        let preset = try preset(id)
        let values = try layer.map { name in try #require(preset.layers.first { $0.name == name }).values }
            ?? preset.values
        let sprites = evaluator.evaluate(placed(values, id: id, duration: preset.duration))
        try #require(!sprites.isEmpty)
        for sprite in sprites {
            let moves = sprite.commands.compactMap { command -> (Double, Double, Double, Double)? in
                guard case let .move(sx, sy, ex, ey) = command.payload else { return nil }
                return (sx, sy, ex, ey)
            }
            let first = try #require(moves.first), last = try #require(moves.last)
            let dx = last.2 - first.0, dy = last.3 - first.1
            #expect(dx > 0 && abs(dy) < dx, "\(id) has a seed going (\(Int(dx)), \(Int(dy)))")
        }
    }

    /// A rooted flower leans; it does not slide. Each one stays put where its
    /// stem meets the ground while its angle moves — and they lean out of
    /// step, or the meadow sways like one cardboard cut-out.
    @Test("the meadow sways about its stems, each flower on its own")
    func meadowSways() throws {
        let preset = try preset("dandelion-sway")
        for layer in preset.layers {
            #expect(layer.values[EmitterEffect.Param.origin] == .choice(Origin.bottomCentre.rawValue),
                    "\(layer.name) is not anchored at its stem")
        }
        let node = clip(preset)
        let early = states(of: node, at: 3000), late = states(of: node, at: 7000)
        #expect(early.count == preset.layers.count)
        var turns: [Double] = []
        for a in early {
            let b = try #require(late.first { $0.spriteId == a.spriteId })
            #expect(abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5, "\(a.spriteId) slid")
            turns.append(b.rotation - a.rotation)
        }
        #expect(turns.contains { abs($0) > 0.005 }, "nothing sways")
        #expect(Set(turns.map { Int(($0 * 1000).rounded()) }).count > 1, "every flower leans in step")
    }

    /// The blown head stays in one piece: the head drawn where it was put,
    /// the seeds born on its fluff and nowhere else, and the anchor drawing
    /// nothing. The sunbeam's lesson, measured the same way.
    /// A parachute flies upright: the seed below, the fluff above. The
    /// texture lies nearly flat, so without `Angle` every seed flew on its
    /// side — and with a random tilt and a spin on top, they tumbled, which
    /// is what "they don't turn right" was.
    @Test("every seed flies upright and never spins", arguments: [
        ("seed-drift", nil), ("seed-gust", nil), ("dandelion-blow", "Seeds"),
    ] as [(String, String?)])
    func seedsStayUpright(id: String, layer: String?) throws {
        let preset = try preset(id)
        let node = clip(preset)
        let prefix = try layer.map { try layerID(preset, $0) } ?? "\(preset.id)/p"
        // Measured against the texture, not against the preset's own constant:
        // a test that reads `seedUpright` agrees with whatever it is set to,
        // and a mutation setting it to zero — every seed on its side — went
        // green. The seed's axis, measured from the alpha of `dandelion_04`,
        // runs 24° above horizontal toward the parachute (−24° in Y-down
        // degrees). Turned by the sprite's rotation, it has to point up (−90°)
        // to within the preset's lean, its random tilt and the flutter.
        let textureAxis = -23.7
        let limit = 4.0 + 8.0 + 8.0 + 2.0
        var seen = 0
        for time in stride(from: 200.0, through: preset.duration - 200, by: 400) {
            for state in states(of: node, at: time) where state.spriteId.hasPrefix(prefix) {
                seen += 1
                let axis = textureAxis + state.rotation * 180 / .pi
                #expect(abs(axis - -90) <= limit,
                        "\(id) has a seed whose stalk points \(Int(axis))° at \(Int(time))ms, not up")
            }
        }
        #expect(seen > 20)
    }

    /// A gust is a change in speed: the seeds arrive fast and the air lets
    /// go of them. A constant speed is a breeze, which the drift already is.
    @Test("a gust arrives fast and slows as it passes")
    func gustSlows() throws {
        let preset = try preset("seed-gust")
        let sprites = evaluator.evaluate(placed(preset.values, id: preset.id, duration: preset.duration))
        try #require(!sprites.isEmpty)
        func x(_ sprite: StoryboardSprite, at time: Double) -> Double {
            let prepared = StoryboardResolver.prepare([sprite])
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: time, into: &states)
            return states[0].x
        }
        var early = 0.0, late = 0.0
        for sprite in sprites {
            early += x(sprite, at: 1000) - x(sprite, at: 0)
            late += x(sprite, at: 5000) - x(sprite, at: 4000)
        }
        #expect(early > late * 3, "the gust moves \(Int(early)) in its first second and \(Int(late)) in its last")
        #expect(late > 0, "the seeds stop dead instead of drifting on")
    }

    @Test("the blown head holds together and its seeds leave from it")
    func blowHoldsTogether() throws {
        let preset = try preset("dandelion-blow")
        let node = clip(preset)
        let head = EmitterEffect.blowHead
        let alive = states(of: node, at: 2000)
        let heads = alive.filter { $0.spriteId.hasPrefix((try? layerID(preset, "Head")) ?? "?") }
        #expect(heads.count == 1)
        // Within the breath's shake: the clip's flutter rocks the head too.
        for state in heads {
            #expect(abs(state.x - head.x) < 20 && abs(state.y - head.y) < 20, "the head is at \(state.x), \(state.y)")
        }
        #expect(!alive.contains { $0.spriteId.hasPrefix("\(preset.id)/p") }, "the anchor draws")

        // One breath: the head is gone soon after, and every seed left in
        // the opening instant rather than trickling off a full head.
        #expect(!states(of: node, at: 2500).contains { $0.spriteId.hasPrefix((try? layerID(preset, "Head")) ?? "?") },
                "the head is still there after its seeds have gone")
        let seeds = try layerID(preset, "Seeds")
        for sprite in evaluator.evaluate(node) where sprite.id.hasPrefix(seeds) {
            let birth = sprite.commands.map(\.startTime).min() ?? 0
            #expect(birth < 50, "a seed leaves the head at \(Int(birth))ms, not in the puff")
            let distance = ((sprite.defaultX - head.x) * (sprite.defaultX - head.x)
                + (sprite.defaultY - (head.y - 30)) * (sprite.defaultY - (head.y - 30))).squareRoot()
            #expect(distance < 100, "a seed is born \(Int(distance))px from the head")
        }
    }
}
