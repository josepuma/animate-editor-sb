import Foundation
import Testing

@testable import StoryboardCore

/// The Backgrounds pack: things that sit behind everything else for as long as
/// their clip runs.
///
/// Three promises, and each is measured off the sprites rather than read off
/// the numbers. A background LASTS its clip — stretched to a minute it is
/// still there at the end. It FILLS the frame rather than sitting in a corner.
/// And it STAYS BACK: dim enough that whatever is placed on top reads over it.
@Suite("Background presets")
struct BackgroundPresetTests {
    private static var all: [EffectPreset] {
        ShapeEffect.presets + EmitterEffect.presets + EmitterEffect.compoundPresets
    }

    static let ids = [
        "dust-motes", "fog-layers", "light-shafts", "cloud-scroll",
        "starfield-parallax", "gradient-backdrop", "vignette",
    ]

    /// The ones made of particles: a field, not a shape.
    static let fields = ["dust-motes", "fog-layers", "starfield-parallax"]

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(Self.all.first { $0.id == id }, "no preset \(id)")
    }

    /// Placed the way the shell places one — the parent AND each layer at its
    /// own position — and stretched to `duration`.
    ///
    /// The parent's position matters because it carries the layers: a
    /// compound moves as one, so a parent placed off centre drags every layer
    /// with it. An earlier version of this helper placed only the layers, and
    /// passed a vignette whose bars had all been dragged 240px up the frame.
    private func sprites(_ preset: EffectPreset, duration: Double) -> [StoryboardSprite] {
        var node = EffectNode(id: preset.id, type: preset.effectType, name: preset.name,
                              startTime: 0, duration: duration, seed: 12, values: preset.values)
        if case let .number(x) = preset.values["x"] { node.transform[value: .x] = x }
        if case let .number(y) = preset.values["y"] { node.transform[value: .y] = y }
        node.layers = preset.layers.enumerated().map { index, layer in
            var child = EffectNode(id: "\(preset.id)/L\(index)", type: layer.effectType, name: layer.name,
                                   startTime: 0, duration: duration,
                                   seed: EffectNode.layerSeed(from: 12, index: index), values: layer.values)
            if case let .number(x) = layer.values["x"] { child.transform[value: .x] = x }
            if case let .number(y) = layer.values["y"] { child.transform[value: .y] = y }
            return child
        }
        return EffectEvaluator().evaluate(node)
    }

    private func states(_ sprites: [StoryboardSprite], at time: Double) -> [SpriteRenderState] {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return states.filter { $0.visible && $0.opacity > 0.01 }
    }

    @Test("every background sits in the Backgrounds pack", arguments: ids)
    func inThePack(id: String) throws {
        #expect(try preset(id).pack == "Backgrounds")
    }

    /// The reason a background is its own family: it has to be there for as
    /// long as the clip runs. Stretched to a minute, still on screen at the
    /// start, the middle and the end.
    @Test("a background lasts its whole clip", arguments: ids)
    func lastsTheClip(id: String) throws {
        let drawn = sprites(try preset(id), duration: 60_000)
        for time in [3000.0, 30_000, 57_000] {
            #expect(!states(drawn, at: time).isEmpty, "\(id) is gone at \(Int(time))ms of a minute")
        }
    }

    /// A field spreads over the frame, not a corner of it.
    @Test("a field fills the frame", arguments: fields)
    func fillsTheFrame(id: String) throws {
        let now = states(sprites(try preset(id), duration: 20_000), at: 10_000)
        let xs = now.map(\.x), ys = now.map(\.y)
        let wide = (xs.max() ?? 0) - (xs.min() ?? 0)
        let tall = (ys.max() ?? 0) - (ys.min() ?? 0)
        #expect(wide > 854 * 0.6 && tall > 480 * 0.6, "\(id) spans \(Int(wide))×\(Int(tall))")
    }

    /// Dim enough that what sits on top reads over it.
    @Test("a field stays in the background", arguments: fields)
    func staysBack(id: String) throws {
        let now = states(sprites(try preset(id), duration: 20_000), at: 10_000)
        let mean = now.map(\.opacity).reduce(0, +) / Double(max(1, now.count))
        #expect(mean <= 0.6, "\(id) averages \(mean) opacity")
    }

    /// Four edges darkening toward the middle: black, painted, one per side.
    @Test("a vignette darkens all four edges")
    func vignette() throws {
        let preset = try preset("vignette")
        let bars = preset.layers.map(\.values)
        #expect(bars.count == 4)
        for values in bars {
            #expect(values[ShapeEffect.Param.fill] == .choice(ShapeEffect.Fill.gradient.rawValue))
            #expect(values[ShapeEffect.Param.color] == .color(EffectColor(r: 0, g: 0, b: 0)))
            #expect(values[ShapeEffect.Param.additive] != .toggle(true))
        }
        let angles = Set(bars.compactMap { values -> Double? in
            if case let .number(angle) = values[ShapeEffect.Param.gradientAngle] { return angle }
            return nil
        })
        #expect(angles == [0, 90, 180, 270], "a side is missing: \(angles)")
    }

    /// Where each bar actually lands, placed as the app places it. Reported
    /// from the app as the whole frame grey with a hard edge low down: the
    /// parent was the top bar, set at y 0, and a compound moves as one — so it
    /// dragged the other three 240px up with it.
    @Test("each vignette bar sits against its own edge")
    func vignetteBarsAtEdges() throws {
        let drawn = sprites(try preset("vignette"), duration: 10_000)
        #expect(drawn.count == 4, "the anchor drew something: \(drawn.count) sprites")
        func bar(_ origin: Origin) -> StoryboardSprite? { drawn.first { $0.origin == origin } }
        #expect(abs((bar(.topCentre)?.defaultY ?? -1) - 0) < 0.5)
        #expect(abs((bar(.bottomCentre)?.defaultY ?? -1) - 480) < 0.5)
        #expect(abs((bar(.centreLeft)?.defaultX ?? 0) + 107) < 0.5)
        #expect(abs((bar(.centreRight)?.defaultX ?? 0) - 747) < 0.5)
        for side in [Origin.centreLeft, .centreRight] {
            #expect(abs((bar(side)?.defaultY ?? -1) - 240) < 0.5)
        }
    }

    @Test("a gradient backdrop covers the frame")
    func gradientCovers() throws {
        let preset = try preset("gradient-backdrop")
        for values in [preset.values] + preset.layers.map(\.values) {
            #expect(values[ShapeEffect.Param.width] == .number(854))
            #expect(values[ShapeEffect.Param.height] == .number(480))
        }
    }
}
