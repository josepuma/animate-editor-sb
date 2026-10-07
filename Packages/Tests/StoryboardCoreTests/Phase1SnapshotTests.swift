import Foundation
import Testing

@testable import StoryboardCore

/// Phase two restructures `TextEffect` and adds axes; these hold that nothing
/// phase one could produce has moved: production against a frozen copy of it
/// (`Phase1TextEffect`, commit be43127d), sprite by sprite and command by
/// command, with no tolerance — save the Rise/Fall exit, which `RiseFallFix`
/// names and rewrites, and which is still compared exactly after the rewrite.
///
/// Compared through `String(reflecting:)` of the same node on both sides, so
/// the sprite ids agree; doubles print their exact value.
@Suite("Text phase 1 snapshot")
struct Phase1SnapshotTests {
    private typealias P = TextEffect.Param

    private static let texts = [
        "HELLO  WORLD",
        "ab c\n\nxyz",
        "ABCDEFGHIJKLMNOPQRSTU",
        "あいう えお",
    ]
    private static let seeds: [UInt64] = [1, 8371, 99123]

    /// Every preset phase one shipped. Named, so presets added later are not
    /// silently held to an oracle that never knew them.
    static let phase1PresetIDs: Set<String> = [
        "typewriter", "fade-up", "drop", "pop-in", "sweep", "scatter",
        "text-shockwave", "unfold", "cascade", "wave", "glitch", "reveal-centre",
        "drift-apart", "burst", "led-sign",
        "word-pop", "line-slide", "assemble", "slam", "stretch-in",
        "spiral-in", "split-reveal", "cascade-wave", "title-drop", "unfold-up",
    ]

    typealias Case = (name: String, duration: Double, values: [String: EffectValue])

    /// One axis at a time over an entrance that moves, fades and staggers, so
    /// each axis meets the arithmetic it can disturb.
    private static let base: [String: EffectValue] = [
        P.fadeIn: .number(300), P.fadeOut: .number(400),
        P.stagger: .number(40), P.riseFrom: .number(30),
    ]

    static let exits = ["Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift"]

    static let axes: [Case] = {
        var cases: [Case] = []
        func add(_ name: String, _ values: [String: EffectValue], duration: Double = 3000) {
            cases.append((name, duration, base.merging(values) { _, new in new }))
        }
        for unit in ["Character", "Word", "Line"] { add("unit \(unit)", [P.unit: .choice(unit)]) }
        for order in ["Start", "End", "Centre", "Random", "Edges", "Wave"] {
            add("order \(order)", [P.staggerFrom: .choice(order), P.waveAmount: .number(1.5)])
        }
        add("spread", [P.staggerMode: .choice("Spread"), P.staggerSpread: .number(70)])
        add("scatter", [
            P.scatterX: .number(120), P.scatterY: .number(80),
            P.scatterRotation: .number(45), P.scatterScale: .number(0.4),
        ])
        add("stretch", [P.stretchFromX: .number(2), P.stretchFromY: .number(0.5)])
        add("pivot", [P.pivot: .choice("Bottom"), P.scaleFrom: .number(0.3)])
        add("drift + spin", [P.driftFrom: .number(-200), P.spinFrom: .number(90)])
        for easing in ["Linear", "Back", "Elastic", "Bounce", "Expo"] {
            add("easing \(easing)", [P.easing: .choice(easing)])
        }
        add("no fade in", [P.fadeIn: .number(0)])
        add("no fades", [P.fadeIn: .number(0), P.fadeOut: .number(0)])
        add("colour", [P.color: .color(EffectColor(r: 255, g: 100, b: 50)), P.additive: .toggle(true)])
        add("no room to leave", [P.stagger: .number(100)], duration: 600)
        for exit in exits {
            for (tx, ty) in [(0.0, 0.0), (30.0, -20.0)] {
                add("exit \(exit) travel \(tx),\(ty)", [
                    P.exit: .choice(exit), P.driftX: .number(tx), P.driftY: .number(ty),
                ])
            }
            add("exit \(exit) stretched", [P.exit: .choice(exit), P.stretchFromX: .number(2)])
        }
        return cases
    }()

    static let cases: [Case] =
        [("defaults", 3000, [:])]
            + TextEffect.presets
            .filter { phase1PresetIDs.contains($0.id) }
            .map { ($0.id, $0.duration, $0.values) }
            + axes

    static func node(
        text: String, seed: UInt64, duration: Double, values: [String: EffectValue],
    ) -> EffectNode {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: duration)
        node.values = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        node.values[TextEffect.Param.text] = .text(text)
        node.seed = seed
        return node
    }

    static func dump(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.map { String(reflecting: $0) }
    }

    static func production(_ node: EffectNode) -> [StoryboardSprite] {
        let context = EffectContext(descriptor: TextEffect.descriptor, node: node)
        var rng = EffectRandom(seed: node.seed)
        return TextEffect().evaluate(in: context, rng: &rng)
    }

    static func oracle(_ node: EffectNode) -> [StoryboardSprite] {
        let context = EffectContext(descriptor: TextEffect.descriptor, node: node)
        var rng = EffectRandom(seed: node.seed)
        return Phase1TextEffect().evaluate(in: context, rng: &rng)
    }

    /// What production must equal for `values`: the oracle, rewritten only
    /// where the named exception applies.
    static func expected(_ node: EffectNode) -> [StoryboardSprite] {
        let sprites = oracle(node)
        return RiseFallFix.applies(node.values)
            ? RiseFallFix.rewrite(sprites, travel: RiseFallFix.travel(node.values))
            : sprites
    }

    @Test("the snapshot runs on the fallback metrics")
    func fallbackMetrics() {
        #expect(TextMetrics.measure == nil)
    }

    @Test("every phase 1 preset is in the matrix")
    func matrixIsComplete() {
        let found = Set(Self.cases.map(\.name)).intersection(Self.phase1PresetIDs)
        #expect(found == Self.phase1PresetIDs)
    }

    @Test("phase 1 output is unchanged, save the named Rise/Fall exit")
    func unchanged() {
        var compared = 0
        for item in Self.cases {
            for text in Self.texts {
                for seed in Self.seeds {
                    let subject = Self.node(
                        text: text, seed: seed, duration: item.duration, values: item.values,
                    )
                    let expected = Self.dump(Self.expected(subject))
                    #expect(
                        Self.dump(Self.production(subject)) == expected,
                        "\(item.name) · \(text.debugDescription) · seed \(seed)",
                    )
                    #expect(!expected.isEmpty)
                    compared += 1
                }
            }
        }
        #expect(compared == Self.cases.count * 4 * 3)
    }

    // ─── The exception itself ────────────────────────────────────────────────

    /// The predicate is exactly the set of nodes whose phase 1 output carried
    /// the `_MY` exit — read from the oracle's own commands, not restated.
    @Test("the excluded set is exactly Rise/Fall with a fade-out")
    func exceptionIsExact() {
        var excluded: [String] = []
        for exit in Self.exits {
            for fadeOut in [0.0, 400] {
                for travel in [0.0, 25] {
                    let values = Self.base.merging([
                        P.exit: .choice(exit), P.fadeOut: .number(fadeOut), P.driftY: .number(travel),
                    ]) { _, new in new }
                    let subject = Self.node(text: "ab cd", seed: 3, duration: 3000, values: values)
                    let writesAxisExit = Self.oracle(subject).contains { sprite in
                        sprite.commands.contains { $0.kind == .moveY }
                    }
                    #expect(RiseFallFix.applies(values) == writesAxisExit, "\(exit) fadeOut \(fadeOut)")
                    if RiseFallFix.applies(values) { excluded.append("\(exit)/\(fadeOut)/\(travel)") }
                }
            }
        }
        #expect(excluded.sorted() == ["Fall/400.0/0.0", "Fall/400.0/25.0", "Rise/400.0/0.0", "Rise/400.0/25.0"])
    }

    /// The rewrite changes the exit and nothing else.
    @Test("the rewrite touches only the exit move")
    func rewriteIsNarrow() throws {
        let values = Self.base.merging([
            P.exit: .choice("Fall"), P.driftX: .number(30), P.driftY: .number(-20),
        ]) { _, new in new }
        let subject = Self.node(text: "abc", seed: 3, duration: 3000, values: values)
        let before = Self.oracle(subject)
        let after = RiseFallFix.rewrite(before, travel: RiseFallFix.travel(values))
        try #require(before.count == after.count && !before.isEmpty)
        for (old, new) in zip(before, after) {
            try #require(old.commands.count == new.commands.count)
            var changed = 0
            for (a, b) in zip(old.commands, new.commands) where String(reflecting: a) != String(reflecting: b) {
                changed += 1
                #expect(a.kind == .moveY && b.kind == .move)
                #expect(a.startTime == b.startTime && a.endTime == b.endTime && a.easing == b.easing)
                if case let .move(sx, sy, ex, ey) = b.payload {
                    #expect(sx == old.defaultX + 30 && ex == sx)
                    #expect(sy == old.defaultY - 20 && ey == sy + 60)
                }
            }
            #expect(changed == 1)
        }
    }
}
