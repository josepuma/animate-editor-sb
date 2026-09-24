import Foundation
import Testing

@testable import StoryboardCore

/// Audio Bars laid out on a circle, an arc or a polygon, drawn as bars, dots
/// or LED segments.
///
/// Every check reads geometry off the sprites — where each bar is rooted and
/// where its tip lands — using the same rotation matrix as `Shaders.metal`, so
/// "points outward" means what the renderer will draw rather than what the
/// numbers seem to say.
@Suite("Audio bars layouts")
struct AudioBarsLayoutTests {
    private let centre = (x: 320.0, y: 240.0)

    /// Every band at one fixed level, so heights are known.
    private func flat(_ level: Float) -> AudioSpectrum.Analyser {
        { range, bands, interval in
            let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
            return AudioSpectrum.Frames(
                levels: Array(repeating: Array(repeating: level, count: bands), count: count),
                interval: interval,
            )
        }
    }

    private func bars(_ values: [String: EffectValue], level: Float = 0.5) -> [StoryboardSprite] {
        var document = EffectDocument()
        let node = document.add(AudioBarsEffect.descriptor, at: 0, duration: 2000)
        for (id, value) in values { document.setValue(value, for: id, on: node.id) }
        return EffectEvaluator(audio: flat(level)).evaluate(document)
    }

    private func rotation(_ sprite: StoryboardSprite) -> Double {
        for command in sprite.commands {
            if case let .rotate(start, _) = command.payload { return start }
        }
        return 0
    }

    /// Where a bar of `length` px drawn up from its origin ends, turned the
    /// way the shader turns it: up is (0, −1), and the standard matrix in a
    /// Y-down space takes it to (sin r, −cos r).
    private func tip(_ sprite: StoryboardSprite, length: Double) -> (x: Double, y: Double) {
        let r = rotation(sprite)
        return (sprite.defaultX + sin(r) * length, sprite.defaultY - cos(r) * length)
    }

    private func distance(_ p: (x: Double, y: Double)) -> Double {
        hypot(p.x - centre.x, p.y - centre.y)
    }

    // ─── Layouts ─────────────────────────────────────────────────────────────

    @Test("the line is still the default layout")
    func lineIsDefault() {
        #expect(AudioBarsEffect.descriptor.defaultValues[AudioBarsEffect.Param.layout] == .choice("Line"))
        #expect(AudioBarsEffect.descriptor.defaultValues[AudioBarsEffect.Param.element] == .choice("Bar"))
    }

    /// Rooted on the ring and pointing away from it: the classic circular
    /// spectrum. A bar turned the wrong way round points at the centre, and
    /// the circle reads as a flower closing.
    @Test("a circle roots every bar on the ring and points it outward")
    func circlePointsOutward() {
        let sprites = bars([
            AudioBarsEffect.Param.layout: .choice("Circle"),
            AudioBarsEffect.Param.radius: .number(120),
            AudioBarsEffect.Param.bands: .integer(24),
        ])
        #expect(sprites.count == 24)
        for sprite in sprites {
            #expect(abs(distance((sprite.defaultX, sprite.defaultY)) - 120) < 0.5)
            #expect(distance(tip(sprite, length: 40)) > 150, "a bar points inward")
        }
        // Evenly around the whole circle: consecutive roots all the same step.
        let angles = sprites.map { atan2($0.defaultY - centre.y, $0.defaultX - centre.x) }
        let steps = zip(angles, angles.dropFirst()).map { b in
            var d = b.1 - b.0
            while d < 0 { d += 2 * .pi }
            return d
        }
        for step in steps { #expect(abs(step - 2 * .pi / 24) < 0.001) }
    }

    /// Top hangs inward from the ring, as it hangs down from a line.
    @Test("growing from the top on a circle points inward")
    func circleInward() {
        let sprites = bars([
            AudioBarsEffect.Param.layout: .choice("Circle"),
            AudioBarsEffect.Param.radius: .number(120),
            AudioBarsEffect.Param.origin: .choice("Top"),
        ])
        for sprite in sprites {
            #expect(sprite.origin == .topCentre)
            // A top-rooted bar extends DOWN its own axis, the opposite of up.
            #expect(distance(tip(sprite, length: -40)) < 90, "a hanging bar points outward")
        }
    }

    @Test("an arc spans the angle it was asked for")
    func arcSpan() {
        let sprites = bars([
            AudioBarsEffect.Param.layout: .choice("Arc"),
            AudioBarsEffect.Param.radius: .number(150),
            AudioBarsEffect.Param.arcSpan: .number(120),
            AudioBarsEffect.Param.bands: .integer(13),
        ])
        let first = try! #require(sprites.first), last = try! #require(sprites.last)
        let a = atan2(first.defaultY - centre.y, first.defaultX - centre.x)
        let b = atan2(last.defaultY - centre.y, last.defaultX - centre.x)
        var span = abs(b - a) * 180 / .pi
        if span > 180 { span = 360 - span }
        #expect(abs(span - 120) < 0.5, "the arc spans \(span)°")
        for sprite in sprites { #expect(abs(distance((sprite.defaultX, sprite.defaultY)) - 150) < 0.5) }
    }

    /// Bars on one edge of a polygon stand parallel — that is what makes it
    /// read as a polygon and not as a circle with corners.
    @Test("a polygon stands its bars square to each edge")
    func polygonEdges() {
        let sprites = bars([
            AudioBarsEffect.Param.layout: .choice("Polygon"),
            AudioBarsEffect.Param.sides: .integer(6),
            AudioBarsEffect.Param.bands: .integer(36),
        ])
        let turns = Set(sprites.map { Int((rotation($0) * 180 / .pi).rounded()) })
        #expect(turns.count == 6, "\(turns.count) distinct directions for a hexagon")
        for sprite in sprites { #expect(distance(tip(sprite, length: 40)) > distance((sprite.defaultX, sprite.defaultY))) }
    }

    // ─── Elements ────────────────────────────────────────────────────────────

    /// A dot rides the tip instead of a bar reaching it: it MOVES with the
    /// level, and a louder song carries it further out.
    @Test("dots ride out with the level instead of scaling")
    func dotsMove() {
        func reach(_ level: Float) -> Double {
            let sprites = bars([
                AudioBarsEffect.Param.layout: .choice("Circle"),
                AudioBarsEffect.Param.element: .choice("Dots"),
            ], level: level)
            let moves = sprites.flatMap(\.commands).compactMap { command -> Double? in
                guard case let .move(_, _, x, y) = command.payload else { return nil }
                return distance((x, y))
            }
            return moves.max() ?? 0
        }
        #expect(reach(0.9) > reach(0.1) + 30, "loud \(reach(0.9)), quiet \(reach(0.1))")

        let sprites = bars([AudioBarsEffect.Param.element: .choice("Dots")])
        #expect(sprites.allSatisfy { sprite in
            !sprite.commands.contains { $0.kind == .vectorScale && $0.startTime > 0 }
        }, "a dot changed size frame by frame")
    }

    /// A column of segments lights from the root up to the level. At half
    /// volume, about half of each column is lit.
    @Test("segments light up to the level, like a meter")
    func segmentsLight() {
        let segments = 10
        let sprites = bars([
            AudioBarsEffect.Param.element: .choice("Segments"),
            AudioBarsEffect.Param.segments: .integer(segments),
            AudioBarsEffect.Param.bands: .integer(4),
        ], level: 0.5)
        #expect(sprites.count == 4 * segments)

        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: 1000, into: &states)
        let lit = states.filter { $0.visible && $0.opacity > 0.5 }.count
        #expect(abs(lit - 4 * segments / 2) <= 4, "\(lit) of \(4 * segments) lit at half volume")
    }

    /// A meter runs a colour ramp up the column, base to peak — green to red
    /// is the classic — so the top segments are the peak colour.
    @Test("segments ramp from the base colour to the peak colour")
    func segmentsRamp() {
        let sprites = bars([
            AudioBarsEffect.Param.element: .choice("Segments"),
            AudioBarsEffect.Param.segments: .integer(5),
            AudioBarsEffect.Param.bands: .integer(2),
            AudioBarsEffect.Param.color: .color(EffectColor(r: 0, g: 255, b: 0)),
            AudioBarsEffect.Param.colorTop: .color(EffectColor(r: 255, g: 0, b: 0)),
        ])
        func red(_ sprite: StoryboardSprite) -> Double {
            for command in sprite.commands {
                if case let .color(r, _, _, _, _, _) = command.payload { return r }
            }
            return -1
        }
        let column = Array(sprites.prefix(5))
        #expect(red(column.first!) < 10)
        #expect(red(column.last!) > 245)
    }
}
