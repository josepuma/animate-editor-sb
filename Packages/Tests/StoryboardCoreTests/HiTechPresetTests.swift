import Foundation
import Testing

@testable import StoryboardCore

/// The Hi-Tech pack, measured from the sprites the editor would draw.
@Suite("Hi-Tech presets")
struct HiTechPresetTests {
    private let evaluator = EffectEvaluator()
    private static let all = ["hud-loader", "hud-target-lock", "hud-data-spinner", "hud-warp-core"]

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(EmitterEffect.compoundPresets.first { $0.id == id }, "no preset \(id)")
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

    /// As `addPreset` builds it — without the filters, so each state is one
    /// layer's own sprite and not its glow copy.
    private func clip(_ preset: EffectPreset) -> EffectNode {
        var node = placed(preset.values, id: preset.id, duration: preset.duration)
        node.layers = preset.layers.enumerated().map { index, layer in
            placed(layer.values, id: "\(preset.id)/L\(index)", duration: preset.duration,
                   seed: EffectNode.layerSeed(from: 12, index: index))
        }
        return node
    }

    private func states(_ preset: EffectPreset, at time: Double) -> [SpriteRenderState] {
        let prepared = StoryboardResolver.prepare(evaluator.evaluate(clip(preset)))
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: time, into: &states)
        return states.filter { $0.visible && $0.opacity > 0.01 }
    }

    private func hudLayers(_ preset: EffectPreset) -> [(index: Int, layer: EffectPreset.Layer)] {
        preset.layers.enumerated().compactMap { index, layer in
            guard case let .text(path) = layer.values[EmitterEffect.Param.sprite],
                  BuiltInSprite.hudShapes.contains(path) else { return nil }
            return (index, layer)
        }
    }

    @Test("every Hi-Tech preset is in its pack, lit, and glows", arguments: all)
    func packAndGlow(id: String) throws {
        let preset = try preset(id)
        #expect(preset.pack == "Hi-Tech")
        #expect(preset.filters.map(\.type) == [GlowFilter.descriptor.type])
        for layer in preset.layers {
            #expect(layer.values[EmitterEffect.Param.additive] == .toggle(true), "\(id)/\(layer.name) is not additive")
        }
        // The anchor draws nothing.
        #expect(preset.values[EmitterEffect.Param.opacity] == .number(0))
    }

    /// Placed as the editor places it, every ring sits on the centre of its
    /// mechanism and stays there while it turns — the anchor shifted nothing.
    @Test("every ring turns in place, on its centre", arguments: all)
    func ringsTurnInPlace(id: String) throws {
        let preset = try preset(id)
        let rings = hudLayers(preset)
        guard !rings.isEmpty else { return }
        for time in [500.0, 2500, 4500] {
            let alive = states(preset, at: time)
            for (index, layer) in rings {
                let state = try #require(alive.first { $0.spriteId.hasPrefix("\(preset.id)/L\(index)/") },
                                         "\(id)/\(layer.name) is not drawn at \(time)")
                let x = layer.values[EmitterEffect.Param.x], y = layer.values[EmitterEffect.Param.y]
                guard case let .number(px) = x, case let .number(py) = y else { continue }
                #expect(abs(state.x - px) < 1 && abs(state.y - py) < 1,
                        "\(id)/\(layer.name) is at \(Int(state.x)), \(Int(state.y))")
            }
        }
    }

    /// Machinery, not a picture spinning: rings turning against each other.
    @Test("every mechanism counter-rotates", arguments: ["hud-loader", "hud-target-lock", "hud-warp-core"])
    func counterRotates(id: String) throws {
        let spins = hudLayers(try preset(id)).compactMap { _, layer -> Double? in
            if case let .number(spin) = layer.values[EmitterEffect.Param.spin] { return spin }
            return nil
        }
        #expect(spins.contains { $0 > 0 } && spins.contains { $0 < 0 }, "\(id) turns all one way: \(spins)")
    }

    /// Four brackets a quarter turn apart, the same size at every moment,
    /// closing in over the clip. The first version had one at `Angle` 270 —
    /// clamped to 180, on top of another — and each its own life, so they
    /// sat at four sizes.
    @Test("the lock's brackets are a square that closes")
    func lockCloses() throws {
        let preset = try preset("hud-target-lock")
        let brackets = preset.layers.enumerated().filter { $0.element.name.hasPrefix("Bracket") }.map(\.offset)
        #expect(brackets.count == 4)
        var sizes: [Double] = []
        for time in [1000.0, 4500] {
            let alive = states(preset, at: time)
            let found = try brackets.map { index in
                try #require(alive.first { $0.spriteId.hasPrefix("\(preset.id)/L\(index)/") })
            }
            let angles = found.map { ($0.rotation * 180 / .pi).truncatingRemainder(dividingBy: 360) }
                .map { $0 < 0 ? $0 + 360 : $0 }
                .map { $0.truncatingRemainder(dividingBy: 90) }
            #expect(angles.allSatisfy { abs($0 - angles[0]) < 0.01 }, "brackets are not a quarter apart: \(angles)")
            let distinctAngles = Set(found.map { Int(($0.rotation * 180 / .pi).rounded()) })
            #expect(distinctAngles.count == 4, "two brackets overlap")
            let scales = found.map(\.scaleX)
            #expect(scales.allSatisfy { abs($0 - scales[0]) < 1e-6 }, "brackets at different sizes: \(scales)")
            sizes.append(scales[0])
        }
        #expect(sizes[1] < sizes[0] * 0.85, "the lock does not close: \(sizes)")
    }
}
