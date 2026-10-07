import Foundation
import Testing

@testable import StoryboardCore

/// Custom and Mirror In, and the exit's own stagger and order, read from the
/// sprites a placed node evaluates to.
@Suite("Text exit")
struct TextExitTests {
    private typealias P = TextEffect.Param

    private static let outParams = [
        P.outRise, P.outDrift, P.outScale, P.outSpin, P.outStretchX, P.outStretchY,
        P.outScatter, P.outScatterRotation, P.outEasing,
    ]

    private func sprites(
        _ values: [String: EffectValue],
        text: String = "abc de",
        duration: Double = 3000,
        seed: UInt64 = 8371,
    ) -> [StoryboardSprite] {
        let node = Phase1SnapshotTests.node(text: text, seed: seed, duration: duration, values: values)
        return Phase1SnapshotTests.production(node)
    }

    private func visible(_ values: [String: EffectValue]) -> Set<String> {
        let all = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        return Set(TextEffect.descriptor.parameters.filter { $0.shownWhen?.holds(in: all) ?? true }.map(\.id))
    }

    private func state(_ sprite: StoryboardSprite, at time: Double) throws -> SpriteRenderState {
        try #require(StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time).first)
    }

    /// When the glyph starts leaving: the start of its fade-out.
    private func exitStarts(_ sprites: [StoryboardSprite]) throws -> [Double] {
        try sprites.map { sprite in
            try #require(sprite.commands.first { command in
                if case .fade(1, 0) = command.payload { true } else { false }
            }).startTime
        }
    }

    private let moving: [String: EffectValue] = [
        P.fadeIn: .number(400), P.fadeOut: .number(500), P.stagger: .number(60),
    ]

    // ─── Parameters ──────────────────────────────────────────────────────────

    @Test("the out parameters show only under Custom")
    func outVisibility() {
        for exit in ["Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift", "Custom", "Mirror In"] {
            let shown = visible([P.exit: .choice(exit)])
            for id in Self.outParams {
                #expect(shown.contains(id) == (exit == "Custom"), "\(exit) · \(id)")
            }
            #expect(shown.contains(P.exitStagger) && shown.contains(P.exitOrder))
        }
    }

    @Test("Custom and Mirror In come after the phase 1 exits")
    func exitOptions() throws {
        let exit = try #require(TextEffect.descriptor.parameters.first { $0.id == P.exit })
        #expect(exit.options == ["Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift", "Custom", "Mirror In"])
    }

    /// The out easing and the mirrored entrance easing read the same table:
    /// each entrance curve's own "in" form.
    @Test("the exit easing table mirrors the entrance one")
    func easingTable() {
        let table: [(String, Easing)] = [
            ("Linear", .linear), ("Ease Out", .in), ("Ease In", .in), ("Back", .backIn),
            ("Elastic", .elasticIn), ("Bounce", .bounceIn), ("Expo", .expoIn),
        ]
        for (name, easing) in table { #expect(TextExit.inEasing(named: name) == easing, "\(name)") }
    }

    // ─── Inertia ─────────────────────────────────────────────────────────────

    /// Exit Stagger at 0 moves nothing, whatever the order says.
    @Test("exit stagger at 0 is inert under every order")
    func staggerZeroIsInert() {
        for order in ["Same", "Reverse", "Start", "End", "Centre", "Edges", "Random"] {
            for mode in ["Per Unit", "Spread"] {
                let values = moving.merging([
                    P.exitOrder: .choice(order), P.staggerMode: .choice(mode), P.exit: .choice("Explode"),
                ]) { _, new in new }
                let node = Phase1SnapshotTests.node(text: "abc de", seed: 5, duration: 3000, values: values)
                #expect(
                    Phase1SnapshotTests.dump(Phase1SnapshotTests.production(node))
                        == Phase1SnapshotTests.dump(Phase1SnapshotTests.expected(node)),
                    "\(order)/\(mode)",
                )
            }
        }
    }

    /// Custom at its defaults goes nowhere, so it is the Fade exit.
    @Test("Custom at its defaults writes what Fade writes")
    func customDefaultsAreFade() {
        let custom = Phase1SnapshotTests.node(
            text: "abc", seed: 5, duration: 3000, values: moving.merging([P.exit: .choice("Custom")]) { _, new in new },
        )
        var fade = custom
        fade.values[P.exit] = .choice("Fade")
        #expect(Phase1SnapshotTests.production(custom).map(\.commands).description
            == Phase1SnapshotTests.production(fade).map(\.commands).description)
    }

    // ─── Order ───────────────────────────────────────────────────────────────

    /// Exits start in the order named: Same follows the entrance, Reverse runs
    /// it backwards, both at the stagger asked for.
    @Test("exit order sets who leaves first")
    func orderSetsExits() throws {
        let same = try exitStarts(sprites(moving.merging([
            P.exitStagger: .number(100), P.exitOrder: .choice("Same"),
        ]) { _, new in new }))
        #expect(same == same.sorted() && Set(same).count == same.count)
        #expect(zip(same, same.dropFirst()).allSatisfy { abs($1 - $0 - 100) < 1e-9 })

        let reverse = try exitStarts(sprites(moving.merging([
            P.exitStagger: .number(100), P.exitOrder: .choice("Reverse"),
        ]) { _, new in new }))
        #expect(reverse == reverse.sorted(by: >) && Set(reverse).count == reverse.count)

        let end = try exitStarts(sprites(moving.merging([
            P.exitStagger: .number(100), P.exitOrder: .choice("End"),
        ]) { _, new in new }))
        #expect(end == reverse)
    }

    /// The last exit still ends with the clip, and every glyph's own exit runs
    /// its full fade-out.
    @Test("a staggered exit keeps its full fade-out and ends inside the clip")
    func staggeredExitSpans() {
        for sprite in sprites(moving.merging([P.exitStagger: .number(100)]) { _, new in new }) {
            let fadeOut = sprite.commands.first { if case .fade(1, 0) = $0.payload { true } else { false } }
            #expect(fadeOut.map { $0.endTime - $0.startTime } == 500)
            #expect((fadeOut?.endTime ?? .infinity) <= 3000)
            #expect(sprite.commands.allSatisfy { $0.endTime <= (fadeOut?.endTime ?? 0) })
        }
    }

    /// Spread scales the entrance into what is left, and the exit stagger
    /// takes its share first: every glyph has landed before the first leaves.
    @Test("Spread leaves room for the exit stagger")
    func spreadCountsExitDelay() throws {
        let drawn = sprites(moving.merging([
            P.staggerMode: .choice("Spread"), P.staggerSpread: .number(100),
            P.exitStagger: .number(150), P.exitOrder: .choice("Same"),
        ]) { _, new in new })
        let landings = try drawn.map { sprite in
            try #require(sprite.commands.first { if case .fade(0, 1) = $0.payload { true } else { false } }).endTime
        }
        let firstExit = try #require(try exitStarts(drawn).min())
        #expect(landings.max() ?? .infinity <= firstExit + 1e-9)
        #expect((landings.max() ?? 0) > 1800, "the spread still uses the room it has")
    }

    // ─── Custom ──────────────────────────────────────────────────────────────

    @Test("Custom goes where it is told, from where the travel left it")
    func customTargets() throws {
        let drawn = sprites(moving.merging([
            P.exit: .choice("Custom"), P.outRise: .number(-50), P.outDrift: .number(30),
            P.outScale: .number(2), P.outSpin: .number(90), P.outEasing: .choice("Back"),
            P.driftX: .number(10), P.driftY: .number(20),
        ]) { _, new in new })
        for sprite in drawn {
            let end = try state(sprite, at: 3000)
            #expect(abs(end.x - (sprite.defaultX + 10 + 30)) < 1e-6)
            #expect(abs(end.y - (sprite.defaultY + 20 - 50)) < 1e-6)
            #expect(abs(end.scaleX - 2) < 1e-9 && abs(end.rotation - .pi / 2) < 1e-9)
            let exitMove = try #require(sprite.commands.last { $0.kind == .move })
            #expect(exitMove.easing == .backIn)
        }
    }

    @Test("Custom scatter throws each glyph its own way, from the seed")
    func customScatter() {
        let values = moving.merging([
            P.exit: .choice("Custom"), P.outScatter: .number(200), P.outScatterRotation: .number(90),
        ]) { _, new in new }
        // The throw itself — how far and how much it turns — not where it
        // lands, which differs per glyph anyway because each starts elsewhere.
        func ends(_ seed: UInt64) -> [String] {
            sprites(values, seed: seed).map { sprite in
                sprite.commands.compactMap { command -> String? in
                    switch command.payload {
                    case let .move(sx, sy, ex, ey): "\(ex - sx),\(ey - sy)"
                    case let .rotate(_, end): "\(end)"
                    default: nil
                    }
                }.joined(separator: " ")
            }
        }
        let a = ends(1)
        #expect(Set(a).count == a.count, "no two glyphs agree")
        #expect(a == ends(1))
        #expect(a != ends(2))
    }

    /// A stretch on the way out makes the whole sprite speak `_V`, entrance
    /// included: osu! multiplies `S` and `V` while the editor lets `V` win.
    @Test("an exit stretch keeps the sprite on _V alone")
    func exitStretchIsVector() {
        let drawn = sprites(moving.merging([
            P.exit: .choice("Custom"), P.outStretchX: .number(2), P.scaleFrom: .number(0.5),
        ]) { _, new in new })
        for sprite in drawn {
            #expect(!sprite.commands.contains { $0.kind == .scale })
            #expect(sprite.commands.contains { command in
                if case .vectorScale(1, 1, 2, 1) = command.payload { true } else { false }
            })
            #expect(sprite.commands.contains { command in
                if case .vectorScale(0.5, 0.5, 1, 1) = command.payload { true } else { false }
            })
        }
    }

    // ─── Mirror In ───────────────────────────────────────────────────────────

    /// The exit is the entrance played back: where the glyph ends is where it
    /// started, scale and turn included, scatter and all.
    @Test("Mirror In leaves the way it came", arguments: ["Linear", "Ease Out", "Back", "Elastic", "Bounce", "Expo"])
    func mirrorReturns(easing: String) throws {
        let drawn = sprites(moving.merging([
            P.exit: .choice("Mirror In"), P.easing: .choice(easing),
            P.riseFrom: .number(80), P.driftFrom: .number(-40), P.scaleFrom: .number(0.5),
            P.spinFrom: .number(90), P.stretchFromY: .number(2),
            P.scatterX: .number(100), P.scatterY: .number(60), P.scatterRotation: .number(30),
        ]) { _, new in new })
        for sprite in drawn {
            let birth = try #require(sprite.commands.first).startTime
            let start = try state(sprite, at: birth)
            let end = try state(sprite, at: 3000)
            #expect(abs(end.x - start.x) < 1e-6 && abs(end.y - start.y) < 1e-6)
            #expect(abs(end.scaleX - start.scaleX) < 1e-9 && abs(end.scaleY - start.scaleY) < 1e-9)
            #expect(abs(end.rotation - start.rotation) < 1e-9)
            let exitMove = try #require(sprite.commands.last { $0.kind == .move })
            #expect(exitMove.easing == TextExit.inEasing(named: easing))
            #expect(exitMove.startTime == 2500)
        }
    }

    /// Halfway out, a mirrored exit is still on its way — not jumped to the
    /// end, not stuck at rest.
    @Test("Mirror In is moving halfway through the exit")
    func mirrorIsMoving() throws {
        let drawn = sprites(moving.merging([
            P.exit: .choice("Mirror In"), P.riseFrom: .number(80), P.easing: .choice("Linear"),
        ]) { _, new in new })
        let sprite = try #require(drawn.first)
        let midway = try state(sprite, at: 2750)
        #expect(abs(midway.y - (sprite.defaultY + 40)) < 1e-6)
    }
}
