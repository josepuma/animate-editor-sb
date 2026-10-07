import Foundation
import Testing

@testable import StoryboardCore

/// No glyph ever carries two commands fighting over one property.
///
/// Swept over every case the phase 1 snapshot holds — presets and one axis at
/// a time — because a new stage (hold, a parametric exit, colour) is exactly
/// what can land on a span another stage already writes.
@Suite("Text overlap guard")
struct TextOverlapGuardTests {
    private typealias P = TextEffect.Param

    private static let texts = ["HELLO  WORLD", "ab c\nxyz"]
    private static let seeds: [UInt64] = [1, 8371]

    private func violations(_ values: [String: EffectValue], duration: Double) -> [String] {
        Self.texts.flatMap { text in
            Self.seeds.flatMap { seed in
                let node = Phase1SnapshotTests.node(text: text, seed: seed, duration: duration, values: values)
                return Phase1SnapshotTests.production(node).flatMap(TextOverlapGuard.violations)
            }
        }
    }

    /// The guard has to be able to fail: a travel `_M` laid over the entrance
    /// `_M`, and a Rise written as `_MY` beside an `_M` entrance.
    @Test("the guard catches a synthetic overlap")
    func guardFires() {
        var sprite = StoryboardSprite(
            id: "probe", layer: .foreground, origin: .centre, filePath: "x.png", defaultX: 0, defaultY: 0,
        )
        sprite.commands = [
            Command(easing: .out, startTime: 0, endTime: 300, payload: .move(startX: 0, startY: 30, endX: 0, endY: 0)),
            Command(easing: .linear, startTime: 200, endTime: 900, payload: .move(startX: 0, startY: 0, endX: 9, endY: 0)),
        ]
        #expect(TextOverlapGuard.violations(sprite).count == 1)

        sprite.commands = [
            Command(easing: .out, startTime: 0, endTime: 300, payload: .move(startX: 0, startY: 30, endX: 0, endY: 0)),
            Command(easing: .quadIn, startTime: 500, endTime: 900, payload: .moveY(start: 0, end: -60)),
        ]
        #expect(TextOverlapGuard.violations(sprite).count == 1)

        sprite.commands = [
            Command(easing: .out, startTime: 0, endTime: 300, payload: .vectorScale(startX: 2, startY: 1, endX: 1, endY: 1)),
            Command(easing: .sineInOut, startTime: 300, endTime: 900, payload: .scale(start: 1, end: 1.1)),
        ]
        #expect(TextOverlapGuard.violations(sprite).count == 1)

        // Touching is how a path is written, and passes.
        sprite.commands = [
            Command(easing: .out, startTime: 0, endTime: 300, payload: .scale(start: 0, end: 1)),
            Command(easing: .quadIn, startTime: 300, endTime: 900, payload: .scale(start: 1, end: 0.2)),
        ]
        #expect(TextOverlapGuard.violations(sprite).isEmpty)
    }

    @Test("no glyph overlaps a family, over every phase 1 case")
    func phase1Matrix() {
        for item in Phase1SnapshotTests.cases {
            let found = violations(item.values, duration: item.duration)
            #expect(found.isEmpty, "\(item.name): \(found.prefix(3))")
        }
    }

    static let allExits = Phase1SnapshotTests.exits + ["Custom", "Mirror In"]

    /// Every exit, staggered and not, over a node whose entrance moves, scales,
    /// stretches and scatters while it travels: each stage has a neighbour to
    /// land on. Custom with every out axis turned, so it writes all three.
    @Test("no glyph overlaps a family, over every exit and exit stagger")
    func exitMatrix() {
        let base: [String: EffectValue] = [
            P.fadeIn: .number(300), P.fadeOut: .number(400), P.stagger: .number(40),
            P.driftX: .number(30), P.driftY: .number(-20), P.riseFrom: .number(40),
            P.stretchFromX: .number(2), P.scatterX: .number(40), P.scatterY: .number(40),
            P.scatterRotation: .number(40), P.scaleFrom: .number(0.5),
            P.outRise: .number(-60), P.outDrift: .number(80), P.outScale: .number(1.5),
            P.outSpin: .number(45), P.outStretchY: .number(2), P.outScatter: .number(50),
        ]
        var checked = 0
        for exit in Self.allExits {
            for stagger in [0.0, 150] {
                for order in ["Same", "Reverse", "Random"] {
                    let values = base.merging([
                        P.exit: .choice(exit), P.exitStagger: .number(stagger), P.exitOrder: .choice(order),
                    ]) { _, new in new }
                    let found = violations(values, duration: 3000)
                    #expect(found.isEmpty, "\(exit) · \(stagger) · \(order): \(found.prefix(3))")
                    checked += 1
                }
            }
        }
        #expect(checked == 10 * 2 * 3)
    }

    static let holds = ["None"] + TextHoldMotionTests.modes

    /// Every hold under every exit and colour mode, staggered and not: the
    /// hold sits between the entrance and the exit on both position and
    /// scale, and the colour shares a glyph's life with all of them. The node
    /// travels, so the folding is checked too, and stretches, so Breathe has
    /// to stay on `_V`.
    @Test("no glyph overlaps a family, over every hold, exit and colour mode")
    func holdColourMatrix() {
        let base: [String: EffectValue] = [
            P.fadeIn: .number(300), P.fadeOut: .number(400), P.stagger: .number(40),
            P.driftX: .number(30), P.driftY: .number(-20), P.riseFrom: .number(40),
            P.stretchFromX: .number(2), P.scatterX: .number(40), P.scatterY: .number(40),
            P.color: .color(EffectColor(r: 255, g: 80, b: 40)), P.colour2: .color(EffectColor(r: 40, g: 80, b: 255)),
            P.sweepLength: .number(80), P.flash: .toggle(true), P.holdAmount: .number(8),
            P.outRise: .number(-60), P.outScale: .number(1.5), P.outSpin: .number(45),
        ]
        var checked = 0
        for hold in Self.holds {
            for exit in Self.allExits {
                for colour in ["Solid", "Gradient", "Highlight"] {
                    for stagger in [0.0, 150] {
                        let values = base.merging([
                            P.holdMotion: .choice(hold), P.exit: .choice(exit),
                            P.colourMode: .choice(colour), P.exitStagger: .number(stagger),
                        ]) { _, new in new }
                        let found = violations(values, duration: 3000)
                        #expect(found.isEmpty, "\(hold) · \(exit) · \(colour) · \(stagger): \(found.prefix(3))")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked == 6 * 10 * 3 * 2)
    }

    /// Every preset under every hold: the presets' own entrances and exits,
    /// with a hold that none of them was written for.
    @Test("no glyph overlaps a family, over every preset under every hold")
    func presetHoldMatrix() {
        for preset in TextEffect.presets {
            for hold in Self.holds {
                for stagger in [0.0, 150] {
                    let values = preset.values.merging([
                        P.holdMotion: .choice(hold), P.exitStagger: .number(stagger),
                    ]) { _, new in new }
                    let found = violations(values, duration: preset.duration)
                    #expect(found.isEmpty, "\(preset.id) · \(hold) · \(stagger): \(found.prefix(3))")
                }
            }
        }
    }

    @Test("no glyph overlaps a family, over every preset with an exit stagger")
    func presetMatrix() {
        for preset in TextEffect.presets {
            for stagger in [0.0, 150] {
                let values = preset.values.merging([P.exitStagger: .number(stagger)]) { _, new in new }
                let found = violations(values, duration: preset.duration)
                #expect(found.isEmpty, "\(preset.id) · \(stagger): \(found.prefix(3))")
            }
        }
    }
}
