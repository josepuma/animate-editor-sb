import Foundation
import Testing

@testable import StoryboardCore

/// The second wave of the library: presets that were missing, and a `Flat`
/// family for storyboards that are drawn rather than lit.
///
/// The generic checks — visible, affordable, not drowning the frame — already
/// run over every preset. These check what each one PROMISES, measured from
/// the sprites it produces rather than read off its numbers: a preset called
/// Converge whose particles fly outward passes every generic check.
@Suite("Preset library")
struct PresetLibraryTests {
    private let evaluator = EffectEvaluator()

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(
            (EmitterEffect.presets + EmitterEffect.compoundPresets).first { $0.id == id },
            "no preset \(id)",
        )
    }

    private func sprites(_ preset: EffectPreset) -> [StoryboardSprite] {
        evaluator.evaluate(EffectNode(
            id: preset.id, type: preset.effectType, name: preset.name,
            startTime: 0, duration: preset.duration, seed: 12, values: preset.values,
        ))
    }

    private struct Path {
        var start: (x: Double, y: Double)
        var end: (x: Double, y: Double)
        var highest: Double
    }

    /// Where a sprite's movement starts and ends, and the highest point it
    /// reaches on the way — a fountain is defined by that last one.
    private func path(_ sprite: StoryboardSprite) -> Path? {
        let moves = sprite.commands
            .compactMap { command -> (Double, Double, Double, Double, Double)? in
                guard case let .move(sx, sy, ex, ey) = command.payload else { return nil }
                return (command.timing.startTime, sx, sy, ex, ey)
            }
            .sorted { $0.0 < $1.0 }
        guard let first = moves.first, let last = moves.last else { return nil }
        let highest = moves.flatMap { [$0.2, $0.4] }.min() ?? first.2
        return Path(start: (first.1, first.2), end: (last.3, last.4), highest: highest)
    }

    private func number(_ preset: EffectPreset, _ id: String) -> Double {
        if case let .number(value) = preset.values[id] { return value }
        return .nan
    }

    private func text(_ preset: EffectPreset, _ id: String) -> String {
        if case let .text(value) = preset.values[id] { return value }
        return ""
    }

    private func toggle(_ preset: EffectPreset, _ id: String) -> Bool {
        if case let .toggle(value) = preset.values[id] { return value }
        return false
    }

    private func choice(_ preset: EffectPreset, _ id: String) -> String {
        if case let .choice(value) = preset.values[id] { return value }
        return ""
    }

    // ─── Flat ────────────────────────────────────────────────────────────────

    static let flatIDs = [
        "pop-dots", "ring-pulse", "pixel-dissolve", "speed-lines", "dot-rain",
        "falling-leaves", "data-rain", "ray-burst", "bubble-pop", "orbit-dots",
    ]

    /// Hard-edged, drawn shapes. A soft dot or a glow is a light, and the
    /// point of this family is storyboards made of shapes.
    private static func hardEdged(_ path: String) -> Bool {
        [BuiltInSprite.disc, BuiltInSprite.fill, BuiltInSprite.square].contains(path)
            || path.hasPrefix("__builtin__/hoop")
    }

    @Test("the flat family is drawn, not lit", arguments: flatIDs)
    func flatIsDrawn(id: String) throws {
        let preset = try preset(id)
        #expect(preset.pack == "Flat", "\(id) should sit in the Flat pack")
        #expect(!toggle(preset, EmitterEffect.Param.additive), "\(id) is additive")
        #expect(Self.hardEdged(text(preset, EmitterEffect.Param.sprite)),
                "\(id) uses a soft sprite: \(text(preset, EmitterEffect.Param.sprite))")
    }

    @Test("shape drift is a compound of different hard shapes, none of them lit")
    func shapeDrift() throws {
        let preset = try preset("shape-drift")
        #expect(preset.pack == "Flat")

        let all = [preset.values] + preset.layers.map(\.values)
        let paths = all.compactMap { values -> String? in
            if case let .text(path) = values[EmitterEffect.Param.sprite] { return path }
            return nil
        }
        #expect(Set(paths).count >= 3, "shapes: \(paths)")
        #expect(paths.allSatisfy { Self.hardEdged($0) }, "shapes: \(paths)")
        #expect(all.allSatisfy { $0[EmitterEffect.Param.additive] != .toggle(true) })
    }

    @Test("pop dots burst out of one point")
    func popDots() throws {
        let preset = try preset("pop-dots")
        #expect(choice(preset, EmitterEffect.Param.emission) == EmitterEffect.Emission.burst.rawValue)

        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 10)
        let origins = Set(paths.map { "\(Int($0.start.x)),\(Int($0.start.y))" })
        #expect(origins.count == 1, "born at \(origins.count) places")
    }

    @Test("a ring pulse is outlines that open")
    func ringPulse() throws {
        let preset = try preset("ring-pulse")
        #expect(text(preset, EmitterEffect.Param.sprite).hasPrefix("__builtin__/hoop"))
        #expect(number(preset, EmitterEffect.Param.scaleEnd) > number(preset, EmitterEffect.Param.scaleStart))
    }

    /// Pixels stay on the grid: a rotated square is a diamond, not a pixel.
    @Test("pixels rise without turning")
    func pixelDissolve() throws {
        let preset = try preset("pixel-dissolve")
        #expect(number(preset, EmitterEffect.Param.spin) == 0)
        #expect(number(preset, EmitterEffect.Param.rotation) == 0)
        #expect(!toggle(preset, EmitterEffect.Param.alignToMotion))

        let paths = sprites(preset).compactMap(path)
        let rising = paths.filter { $0.end.y < $0.start.y }.count
        #expect(Double(rising) > Double(paths.count) * 0.9, "\(rising) of \(paths.count) rise")
    }

    @Test("speed lines run across the frame, not up or down it")
    func speedLines() throws {
        let preset = try preset("speed-lines")
        #expect(toggle(preset, EmitterEffect.Param.alignToMotion))
        #expect(number(preset, EmitterEffect.Param.stretch) >= 4)

        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 10)
        for p in paths {
            let dx = abs(p.end.x - p.start.x)
            let dy = abs(p.end.y - p.start.y)
            #expect(dx > dy * 5, "a line drifts \(Int(dy)) for \(Int(dx)) across")
        }
    }

    @Test("dots rain down")
    func dotRain() throws {
        let paths = try sprites(preset("dot-rain")).compactMap(path)
        #expect(paths.count > 10)
        #expect(paths.allSatisfy { $0.end.y > $0.start.y })
    }

    // ─── Lit ─────────────────────────────────────────────────────────────────

    /// The one a charge is made of. Every particle has to END nearer the
    /// centre than it began — a converge that sprays outward is a burst with
    /// the wrong name, and Radial's own default points out.
    @Test("converge pulls every particle toward the centre")
    func converge() throws {
        let preset = try preset("converge")
        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 10)

        // The stage centre, not the preset's `x`/`y`: the emitter never reads
        // those — the editor lifts them onto the transform — so a node
        // evaluated bare emits around the middle of the stage.
        let centre = (x: 320.0, y: 240.0)
        func distance(_ p: (x: Double, y: Double)) -> Double {
            hypot(p.x - centre.x, p.y - centre.y)
        }
        let inward = paths.filter { distance($0.end) < distance($0.start) * 0.5 }.count
        #expect(Double(inward) > Double(paths.count) * 0.9, "\(inward) of \(paths.count) close in")
    }

    @Test("fireflies wander slowly and glow")
    func fireflies() throws {
        let preset = try preset("fireflies")
        #expect(toggle(preset, EmitterEffect.Param.additive))
        #expect(number(preset, EmitterEffect.Param.velocity) <= 40)
    }

    @Test("glitter falls and turns")
    func glitterFall() throws {
        let preset = try preset("glitter-fall")
        #expect(text(preset, EmitterEffect.Param.sprite) == BuiltInSprite.sparkle)
        #expect(number(preset, EmitterEffect.Param.spin) != 0)

        let paths = sprites(preset).compactMap(path)
        let falling = paths.filter { $0.end.y > $0.start.y }.count
        #expect(Double(falling) > Double(paths.count) * 0.9)
    }

    /// Up, then down: the arc is the whole preset. Most particles have to
    /// climb above where they started AND come back down past their peak.
    @Test("a fountain rises and falls back")
    func fountain() throws {
        let paths = try sprites(preset("fountain")).compactMap(path)
        #expect(paths.count > 10)
        let arcs = paths.filter { $0.highest < $0.start.y - 20 && $0.end.y > $0.highest + 20 }.count
        #expect(Double(arcs) > Double(paths.count) * 0.7, "\(arcs) of \(paths.count) arc")
    }

    @Test("a galaxy is a tilted disc that swirls")
    func galaxy() throws {
        let preset = try preset("galaxy")
        #expect(number(preset, EmitterEffect.Param.tilt) > 0)
        #expect(number(preset, EmitterEffect.Param.swirl) != 0)
        #expect(toggle(preset, EmitterEffect.Param.radial))
    }

    /// Not "climbs, then bursts": every layer of a compound starts at local
    /// zero and the emitter has no per-layer delay, so a rocket rising before
    /// its burst is not something a compound can say. What it can say is the
    /// burst, the flash and the glitter coming down after — so that is the
    /// promise.
    @Test("a firework bursts, flashes and leaves glitter")
    func firework() throws {
        let preset = try preset("firework")
        #expect(preset.layers.count >= 2)
        #expect(choice(preset, EmitterEffect.Param.emission) == EmitterEffect.Emission.burst.rawValue)
        #expect(toggle(preset, EmitterEffect.Param.radial))

        let glitter = preset.layers.contains { layer in
            layer.values[EmitterEffect.Param.sprite] == .text(BuiltInSprite.sparkle)
        }
        #expect(glitter, "no glitter layer")
    }

    // ─── Sprites ─────────────────────────────────────────────────────────────

    /// A hoop names its weight in its path, so it is a family of images rather
    /// than one — and the flat family needs it. The check that a preset names
    /// a real sprite has to know that, or an outline is reported as missing.
    @Test("a hoop is a known sprite, a stray name is not")
    func hoopsAreKnown() {
        #expect(BuiltInSprite.isKnown(BuiltInSprite.hoop(thickness: 0.06)))
        #expect(BuiltInSprite.isKnown(BuiltInSprite.disc))
        #expect(!BuiltInSprite.isKnown("__builtin__/hoop999.png"))
        #expect(!BuiltInSprite.isKnown("__builtin__/hoopish.png"))
        #expect(!BuiltInSprite.isKnown("sb/particle.png"))
    }

    // ─── Third wave: after Particle Illusion's categories ────────────────────

    private func falls(_ paths: [Path]) -> Bool {
        Double(paths.filter { $0.end.y > $0.start.y }.count) > Double(paths.count) * 0.9
    }

    /// A petal is a flat piece tumbling: squashed on one axis and turning, so
    /// it flips between edge-on and face-on as it falls. Paint, not light.
    @Test("petals and leaves are squashed pieces tumbling down", arguments: ["petals", "falling-leaves"])
    func tumbling(id: String) throws {
        let preset = try preset(id)
        #expect(number(preset, EmitterEffect.Param.stretch) < 1)
        #expect(number(preset, EmitterEffect.Param.spin) != 0)
        #expect(!toggle(preset, EmitterEffect.Param.additive))
        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 10)
        #expect(falls(paths))
    }

    @Test("a nebula is large slow light")
    func nebula() throws {
        let preset = try preset("nebula")
        #expect(text(preset, EmitterEffect.Param.sprite) == BuiltInSprite.cloud)
        #expect(toggle(preset, EmitterEffect.Param.additive))
        #expect(number(preset, EmitterEffect.Param.velocity) <= 15)
    }

    /// Curtains hang: an aurora that tumbles is smoke.
    @Test("an aurora is hanging curtains of light")
    func aurora() throws {
        let preset = try preset("aurora")
        #expect(text(preset, EmitterEffect.Param.sprite) == BuiltInSprite.cloudWisp)
        #expect(toggle(preset, EmitterEffect.Param.additive))
        #expect(number(preset, EmitterEffect.Param.rotation) == 0)
        #expect(number(preset, EmitterEffect.Param.spin) == 0)
    }

    @Test("light streaks cross the frame sideways")
    func lightStreaks() throws {
        let preset = try preset("light-streaks")
        #expect(text(preset, EmitterEffect.Param.sprite) == BuiltInSprite.beam)
        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 5)
        #expect(paths.allSatisfy { abs($0.end.x - $0.start.x) > abs($0.end.y - $0.start.y) * 5 })
    }

    /// Short, fast and branching: the spark texture is what branches, and a
    /// long life turns a sparkler into a fountain.
    @Test("a sparkler throws short-lived branching sparks from one point")
    func sparkler() throws {
        let preset = try preset("sparkler")
        #expect(choice(preset, EmitterEffect.Param.shape) == EmitterEffect.Shape.point.rawValue)
        #expect(text(preset, EmitterEffect.Param.sprite).contains("spark_"))
        #expect(number(preset, EmitterEffect.Param.life) <= 400)
    }

    @Test("a splash throws drops in an arc and leaves a ripple")
    func splash() throws {
        let preset = try preset("splash")
        let paths = sprites(preset).compactMap(path)
        let arcs = paths.filter { $0.highest < $0.start.y - 15 && $0.end.y > $0.highest + 15 }.count
        #expect(Double(arcs) > Double(paths.count) * 0.7, "\(arcs) of \(paths.count) arc")
        #expect(preset.layers.contains { layer in
            if case let .text(path) = layer.values[EmitterEffect.Param.sprite] {
                return path.hasPrefix("__builtin__/hoop")
            }
            return false
        })
    }

    /// Everything falls in, and the middle is dark. The dark core has to be
    /// the LAST layer: draw order is layer order, and a horizon drawn under
    /// the light it swallows is not a horizon.
    @Test("a black hole swallows light around a dark centre")
    func blackHole() throws {
        let preset = try preset("black-hole")
        let last = try #require(preset.layers.last)
        #expect(last.values[EmitterEffect.Param.additive] == .toggle(false))
        if case let .color(colour) = last.values[EmitterEffect.Param.color] {
            #expect(colour.r + colour.g + colour.b < 60, "the horizon is \(colour)")
        } else {
            Issue.record("the horizon has no colour")
        }

        let infall = try #require(preset.layers.first { $0.name == "Infall" })
        let paths = evaluator.evaluate(EffectNode(
            id: "infall", type: infall.effectType, name: infall.name,
            startTime: 0, duration: preset.duration, seed: 12, values: infall.values,
        )).compactMap(path)
        func distance(_ p: (x: Double, y: Double)) -> Double { hypot(p.x - 320, p.y - 240) }
        let inward = paths.filter { distance($0.end) < distance($0.start) * 0.5 }.count
        #expect(Double(inward) > Double(paths.count) * 0.9, "\(inward) of \(paths.count) fall in")
    }

    @Test("data rain falls straight down")
    func dataRain() throws {
        let preset = try preset("data-rain")
        #expect(toggle(preset, EmitterEffect.Param.alignToMotion))
        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 10)
        #expect(paths.allSatisfy { abs($0.end.y - $0.start.y) > abs($0.end.x - $0.start.x) * 5 && $0.end.y > $0.start.y })
    }

    @Test("a ray burst fires aligned strokes out of one point")
    func rayBurst() throws {
        let preset = try preset("ray-burst")
        #expect(choice(preset, EmitterEffect.Param.emission) == EmitterEffect.Emission.burst.rawValue)
        #expect(toggle(preset, EmitterEffect.Param.alignToMotion))
        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 5)
        #expect(Set(paths.map { "\(Int($0.start.x)),\(Int($0.start.y))" }).count == 1)
    }

    @Test("bubbles pop on the way up")
    func bubblePop() throws {
        let preset = try preset("bubble-pop")
        #expect(text(preset, EmitterEffect.Param.sprite).hasPrefix("__builtin__/hoop"))
        let paths = sprites(preset).compactMap(path)
        #expect(Double(paths.filter { $0.end.y < $0.start.y }.count) > Double(paths.count) * 0.9)
    }

    /// Orbiting is running ALONG the ring, not away from it: each dot leaves
    /// on the tangent, so its travel is nearly perpendicular to the line back
    /// to the centre. Pointing outward is a burst.
    @Test("orbit dots run along their ring")
    func orbitDots() throws {
        let preset = try preset("orbit-dots")
        #expect(choice(preset, EmitterEffect.Param.shape) == EmitterEffect.Shape.ring.rawValue)
        let paths = sprites(preset).compactMap(path)
        #expect(paths.count > 10)

        let tangential = paths.filter { p in
            let rx = p.start.x - 320, ry = p.start.y - 240
            let mx = p.end.x - p.start.x, my = p.end.y - p.start.y
            let r = hypot(rx, ry), m = hypot(mx, my)
            guard r > 0, m > 0 else { return false }
            return abs((rx * mx + ry * my) / (r * m)) < 0.4
        }.count
        #expect(Double(tangential) > Double(paths.count) * 0.8, "\(tangential) of \(paths.count) orbit")
    }

    // ─── Audio ───────────────────────────────────────────────────────────────

    /// Each audio preset has to actually listen — an "audio" preset on a
    /// continuous emission is a plain emitter with a promising name.
    @Test("audio presets listen to the song", arguments: [
        ("spectrum-fountain", "All"), ("bass-burst", "Bass"),
        ("treble-sparkles", "Highs"), ("beat-dots", "All"),
    ])
    func audioPresetsListen(id: String, band: String) throws {
        let preset = try preset(id)
        #expect(preset.pack == "Audio")
        #expect(choice(preset, EmitterEffect.Param.emission) == EmitterEffect.Emission.audio.rawValue)
        #expect(choice(preset, EmitterEffect.Param.audioBand) == band)
    }

    @Test("the spectrum presets emit from a spectrum", arguments: ["spectrum-fountain", "beat-dots"])
    func spectrumPresets(id: String) throws {
        #expect(choice(try preset(id), EmitterEffect.Param.shape) == EmitterEffect.Shape.spectrum.rawValue)
    }

    /// The flat one keeps the flat family's rules even outside its pack.
    @Test("beat dots are drawn, not lit")
    func beatDotsAreFlat() throws {
        let preset = try preset("beat-dots")
        #expect(!toggle(preset, EmitterEffect.Param.additive))
        #expect(Self.hardEdged(text(preset, EmitterEffect.Param.sprite)))
    }
}
