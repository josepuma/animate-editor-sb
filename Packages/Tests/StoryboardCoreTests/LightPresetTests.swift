import Foundation
import Testing

@testable import StoryboardCore

/// The Light pack: shafts drawn by the sunshine textures.
///
/// The generic checks — visible, sized, not drowning the frame — run over
/// every preset already. These check what this pack promises, measured from
/// the sprites it produces: that a shaft stays put, that its copies line up,
/// that it hangs from its source, and that the sunbeam's dust is in the light.
@Suite("Light presets")
struct LightPresetTests {
    private let evaluator = EffectEvaluator()

    private static let shafts = ["god-rays", "sun-fan", "sun-rays", "stage-lights", "spotlight-pulse", "sunbeam"]

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(
            (EmitterEffect.presets + EmitterEffect.compoundPresets).first { $0.id == id },
            "no preset \(id)",
        )
    }

    /// One emitter placed exactly as `EditorShellModel.addPreset` places it.
    ///
    /// The emitter never reads `x`/`y`: the editor lifts them onto the
    /// transform, where they are absolute stage positions. Evaluated without
    /// that, every shaft sits dead centre and no position check means anything.
    private func placed(_ values: [String: EffectValue], id: String, duration: Double, seed: UInt64 = 12) -> EffectNode {
        var node = EffectNode(
            id: id, type: EmitterEffect.descriptor.type, name: id,
            startTime: 0, duration: duration, seed: seed, values: values,
        )
        if case let .number(x) = values[EmitterEffect.Param.x] { node.transform[value: .x] = x }
        if case let .number(y) = values[EmitterEffect.Param.y] { node.transform[value: .y] = y }
        return node
    }

    /// A whole compound, built the way `EditorShellModel.addPreset` builds it:
    /// the parent's position on its transform, each layer a child node with
    /// its own. Evaluating layers one by one is what let a sunbeam render fine
    /// in a probe while the editor tore it apart — the parent's transform
    /// carries the whole group, and only this path runs it.
    private func placedCompound(_ preset: EffectPreset) -> EffectNode {
        var node = placed(preset.values, id: preset.id, duration: preset.duration)
        node.layers = preset.layers.enumerated().map { index, layer in
            var child = placed(
                layer.values, id: "\(preset.id)/L\(index)", duration: preset.duration,
                seed: EffectNode.layerSeed(from: 12, index: index),
            )
            child.name = layer.name
            return child
        }
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

    /// The emitter that draws the shaft: the preset itself, or — in a
    /// compound whose parent is an anchor — its Body layer.
    private func shaft(_ preset: EffectPreset) -> [String: EffectValue] {
        preset.layers.first { $0.name == "Body" }?.values ?? preset.values
    }

    /// The shaft alone, without its other layers or filters.
    private func states(_ preset: EffectPreset, at fraction: Double) -> [SpriteRenderState] {
        states(of: placed(shaft(preset), id: preset.id, duration: preset.duration), at: preset.duration * fraction)
    }

    @Test("every light preset is in the Light pack and draws a sunshine texture", arguments: shafts)
    func packAndTexture(id: String) throws {
        let preset = try preset(id)
        #expect(preset.pack == "Light")
        let values = shaft(preset)
        guard case let .text(path) = values[EmitterEffect.Param.sprite] else {
            Issue.record("\(id) names no sprite")
            return
        }
        #expect(BuiltInSprite.fileSizes[path] != nil, "\(id) does not use a shipped light texture")
        #expect(values[EmitterEffect.Param.additive] == .toggle(true), "\(id) is not additive")
    }

    /// A shaft is a shape in a place. One that drifts is a sprite sliding
    /// across the frame, which no light does.
    @Test("a shaft never moves", arguments: shafts)
    func shaftsStayPut(id: String) throws {
        let preset = try preset(id)
        let first = states(preset, at: 0.35)
        let later = states(preset, at: 0.45)
        try #require(!first.isEmpty, "\(id) draws nothing")
        // Every position seen later has to be one already seen — copies come
        // and go, but none of them travels.
        for state in later {
            let held = first.contains { abs($0.x - state.x) < 0.5 && abs($0.y - state.y) < 0.5 }
            let born = !first.contains { $0.spriteId == state.spriteId }
            #expect(held || born, "\(id) has a shaft at \(state.x), \(state.y) that moved")
        }
    }

    /// Copies of one shaft have to line up. Tilted or sized even a little
    /// differently, the brush's fine streaks smear into haze — the first
    /// version of this pack, which rendered as mush. The breathing comes from
    /// the copies cross-fading, never from them disagreeing.
    @Test("a shaft's copies line up: one angle, one size", arguments: shafts)
    func copiesLineUp(id: String) throws {
        let alive = states(try preset(id), at: 0.5)
        #expect(alive.count >= 2, "\(id) has \(alive.count) copies alive at once")
        if id == "sun-rays" { return } // spread on purpose, sized a little apart
        let angles = Set(alive.map { Int(($0.rotation * 1000).rounded()) })
        let sizes = Set(alive.map { Int(($0.scaleY * 1000).rounded()) })
        #expect(angles.count == 1, "\(id)'s copies sit at \(angles.count) angles")
        #expect(sizes.count == 1, "\(id)'s copies come in \(sizes.count) sizes")
    }

    /// Every shaft hangs from its source: the position is where the light
    /// comes from, so `Angle` pivots it there instead of swinging it about its
    /// middle.
    @Test("every shaft is anchored at its source", arguments: shafts)
    func shaftsAreAnchoredAtTheSource(id: String) throws {
        let preset = try preset(id)
        for values in [preset.values] + preset.layers.map(\.values) {
            guard case let .text(path) = values[EmitterEffect.Param.sprite],
                  BuiltInSprite.fileSizes[path] != nil,
                  values[EmitterEffect.Param.rotation] != .number(360) else { continue }
            #expect(values[EmitterEffect.Param.origin] == .choice(Origin.topCentre.rawValue),
                    "\(id) has a shaft not anchored TopCentre")
        }
    }

    /// The dust has to hang inside the beam it lights up. Thrown the wrong way
    /// it drifts beside the shaft in the dark, which no dust in a sunbeam does
    /// — the first version subtracted the angle and did exactly that.
    @Test("the sunbeam's dust settles inside the shaft")
    func dustIsInTheBeam() throws {
        let preset = try preset("sunbeam")
        let node = placedCompound(preset)
        let dust = try layerID(preset, "Dust")
        let source = EmitterEffect.sunbeamSource
        // Down the lean: a sprite's down (0, 1) turned by the angle.
        let lean = EmitterEffect.sunbeamAngle * .pi / 180
        let axis = (x: -sin(lean), y: cos(lean))

        var inside = 0, total = 0
        for fraction in [0.4, 0.6, 0.8] {
            for state in states(of: node, at: preset.duration * fraction) where state.spriteId.hasPrefix(dust) {
                let dx = state.x - source.x, dy = state.y - source.y
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance > 20 else { continue }
                total += 1
                if (dx * axis.x + dy * axis.y) / distance > cos(25 * Double.pi / 180) { inside += 1 }
            }
        }
        try #require(total > 50, "only \(total) motes to measure")
        #expect(Double(inside) / Double(total) > 0.85, "\(inside) of \(total) motes are inside the shaft")
    }

    /// Each brush starts on a hard edge where its light comes from. Inside
    /// the frame that edge reads as a stick of light sawn off — so every copy
    /// of every shaft, layers included, has to keep its source above the top.
    @Test("every shaft's source is above the frame", arguments: shafts)
    func sourcesAreOffScreen(id: String) throws {
        let preset = try preset(id)
        let emitters = [(preset.values, preset.id)]
            + preset.layers.enumerated().map { ($1.values, "\(preset.id)/L\($0)") }
        for (values, nodeID) in emitters {
            guard case let .text(path) = values[EmitterEffect.Param.sprite],
                  let size = BuiltInSprite.fileSizes[path] else { continue }
            // A source in the frame is allowed when something bright sits on
            // it and becomes the light — the sunbeam's Source layer.
            let x = values[EmitterEffect.Param.x], y = values[EmitterEffect.Param.y]
            if preset.layers.contains(where: { layer in
                layer.name == "Source"
                    && layer.values[EmitterEffect.Param.x] == x
                    && layer.values[EmitterEffect.Param.y] == y
            }) { continue }
            let anchored = values[EmitterEffect.Param.origin] == .choice(Origin.topCentre.rawValue)
            let node = placed(values, id: nodeID, duration: preset.duration)
            for fraction in stride(from: 0.1, through: 0.9, by: 0.1) {
                for state in states(of: node, at: preset.duration * fraction) {
                    // Anchored at the source, the position *is* the top edge.
                    let top = anchored
                        ? state.y
                        : state.y - abs(cos(state.rotation)) * state.scaleY * size.height / 2
                    #expect(top < 0, "\(nodeID) has a shaft whose source is at y \(Int(top))")
                }
            }
        }
    }

    /// Placed as the editor places it, every part of the sunbeam has to sit
    /// on its source: the shaft hanging from it, the glow and the disc on top
    /// of it. The first version left the shaft at the stage centre, torn away
    /// from its own light, and nothing that evaluated layers one at a time
    /// could see it.
    @Test("the sunbeam holds together when placed as the editor places it")
    func sunbeamHoldsTogether() throws {
        let preset = try preset("sunbeam")
        let alive = states(of: placedCompound(preset), at: preset.duration * 0.5)
        let source = EmitterEffect.sunbeamSource
        for name in ["Body", "Streaks", "Burst", "Glow", "Source"] {
            let prefix = try layerID(preset, name)
            let part = alive.filter { $0.spriteId.hasPrefix(prefix) }
            #expect(!part.isEmpty, "the sunbeam's \(name) draws nothing")
            for state in part {
                #expect(abs(state.x - source.x) < 1 && abs(state.y - source.y) < 1,
                        "the sunbeam's \(name) is at \(Int(state.x)), \(Int(state.y)), not on its source")
            }
        }
        // The anchor draws nothing: it only holds the group in place.
        #expect(!alive.contains { $0.spriteId.hasPrefix("\(preset.id)/p") })
    }

    /// Light through leaves is a ray here and a ray there. Piled on one
    /// point it is one shaft flickering.
    @Test("sun rays are spread along the top")
    func sunRaysSpread() throws {
        let preset = try preset("sun-rays")
        let xs = stride(from: 0.1, through: 0.9, by: 0.1).flatMap { states(preset, at: $0).map(\.x) }
        let spread = try #require(xs.max()) - (try #require(xs.min()))
        #expect(spread > 300, "sun rays only spread \(Int(spread)) across")
    }

    /// The two that follow the song carry the filter that makes them do it.
    @Test("stage lights and the spotlight listen to the song")
    func listeningPresetsCarryTheirFilters() throws {
        #expect(try preset("stage-lights").filters.map(\.type) == [AudioDriveFilter.descriptor.type])
        #expect(try preset("spotlight-pulse").filters.map(\.type) == [PulseFilter.descriptor.type])
    }
}
