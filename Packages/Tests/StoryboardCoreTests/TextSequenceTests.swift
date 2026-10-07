import Foundation
import Testing

@testable import StoryboardCore

/// Unit, Order and Stagger Mode through the evaluator, on a node placed the way
/// the editor places one — the sprites it produces, not the formula behind them.
@Suite("Text sequence")
struct TextSequenceTests {
    private func sprites(
        _ text: String,
        duration: Double = 4000,
        _ values: [String: EffectValue] = [:],
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: duration)
        node.values = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        node.values[TextEffect.Param.text] = .text(text)
        node.values[TextEffect.Param.fadeIn] = node.values[TextEffect.Param.fadeIn] == .number(0)
            ? .number(200) : node.values[TextEffect.Param.fadeIn]
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    /// When each glyph starts arriving: the start of its first fade.
    private func arrivals(_ sprites: [StoryboardSprite]) -> [Double] {
        sprites.map { sprite in
            sprite.commands.first { if case .fade = $0.payload { true } else { false } }!.startTime
        }
    }

    private typealias P = TextEffect.Param

    /// S2.1
    @Test("Word makes a word's glyphs arrive together")
    func wordsShareDelay() {
        let word = arrivals(sprites("ab cd", [P.stagger: .number(100), P.unit: .choice("Word")]))
        #expect(word[0] == word[1])
        #expect(word[2] == word[3])
        #expect(word[2] > word[0])

        let character = arrivals(sprites("ab cd", [P.stagger: .number(100)]))
        #expect(Set(character).count == 4)
    }

    /// S2.2
    @Test("Line makes a line's glyphs arrive together")
    func linesShareDelay() {
        let line = arrivals(sprites("ab\ncd", [P.stagger: .number(100), P.unit: .choice("Line")]))
        #expect(line[0] == line[1])
        #expect(line[2] == line[3])
        #expect(line[2] > line[0])
    }

    /// S2.3
    @Test("punctuation belongs to its word")
    func punctuation() {
        // h o l a , m u n d o !
        let word = arrivals(sprites("hola, mundo!", [P.stagger: .number(100), P.unit: .choice("Word")]))
        #expect(Set(word[0...4]).count == 1, "\"hola,\" is one unit")
        #expect(Set(word[5...10]).count == 1, "\"mundo!\" is one unit")
        #expect(word[5] > word[0])
    }

    /// S2.4: spaces never make empty units, so ranks have no gaps.
    @Test("runs of spaces and blank lines leave no gaps")
    func denseUnits() {
        let words = arrivals(sprites("a   b", [P.stagger: .number(100), P.unit: .choice("Word")]))
        #expect(words.count == 2)
        #expect(words[1] - words[0] == 100, "one rank apart however many spaces")

        let lines = arrivals(sprites("a\n\n\nb", [P.stagger: .number(100), P.unit: .choice("Line")]))
        #expect(lines[1] - lines[0] == 100, "blank lines are not lines")
    }

    /// S2.5
    @Test("Character is the legacy behaviour")
    func characterIsDefault() {
        // One node, so sprite ids match: two placements would mint two ids and
        // differ on that alone. Random order, so a shifted rng would show.
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 3000)
        node.values = [
            P.text: .text("hello, world"), P.stagger: .number(60), P.fadeIn: .number(200),
            P.staggerFrom: .choice("Random"), P.unit: .choice("Character"),
        ]
        node.seed = 8371
        let context = EffectContext(descriptor: TextEffect.descriptor, node: node)
        var production = EffectRandom(seed: node.seed)
        var legacy = EffectRandom(seed: node.seed)
        let explicit = TextEffect().evaluate(in: context, rng: &production)
        let expected = LegacyTextEffect().evaluate(in: context, rng: &legacy)
        #expect(!expected.isEmpty)
        #expect(explicit.map { String(reflecting: $0) } == expected.map { String(reflecting: $0) })
    }

    /// S3.1 through the evaluator.
    @Test("Edges arrive from both ends")
    func edges() {
        let a = arrivals(sprites("abcdef", [P.stagger: .number(100), P.staggerFrom: .choice("Edges")]))
        #expect(a == [0, 100, 200, 200, 100, 0])
    }

    /// S4.1: with Spread the last unit arrives at its share of the room.
    @Test("Spread places the last arrival at its share of the window")
    func spread() {
        let values: [String: EffectValue] = [
            P.staggerMode: .choice("Spread"), P.staggerSpread: .number(50),
            P.fadeIn: .number(500), P.fadeOut: .number(500),
        ]
        let a = arrivals(sprites("abcd", duration: 4000, values))
        #expect(a.first == 0)
        #expect(abs(a.last! - 0.5 * (4000 - 500 - 500)) < 1e-9)
    }

    /// S4.2: even at 100% nobody is still arriving when the exit begins.
    @Test("Spread at 100% never overlaps the exit")
    func spreadNeverOverlapsExit() {
        let values: [String: EffectValue] = [
            P.staggerMode: .choice("Spread"), P.staggerSpread: .number(100),
            P.fadeIn: .number(600), P.fadeOut: .number(400),
        ]
        let all = sprites("the quick brown fox", duration: 3000, values)
        for sprite in all {
            let fades = sprite.commands.compactMap { command -> Command? in
                if case .fade = command.payload { command } else { nil }
            }
            let arrival = fades.first!
            // A real fade-out, at the shared exit time. The evaluator rescues a
            // late glyph by pushing its exit back or dropping it, so "no overlap"
            // alone would pass with a window that ignores the exit: what Spread
            // promises is that nobody needs rescuing.
            let exit = fades.last {
                if case .fade(start: 1, end: 0) = $0.payload { true } else { false }
            }
            #expect(exit != nil, "every glyph still has its exit")
            if let exit {
                #expect(exit.startTime == 3000 - 400)
                #expect(arrival.endTime <= exit.startTime + 1e-9)
            }
        }
    }

    /// S4.3
    @Test("a single unit with Spread is finite")
    func singleUnitFinite() {
        let values: [String: EffectValue] = [
            P.staggerMode: .choice("Spread"), P.staggerSpread: .number(100), P.unit: .choice("Line"),
        ]
        let all = sprites("one line", values)
        #expect(Set(arrivals(all)) == [0])
        for sprite in all {
            for command in sprite.commands {
                #expect(command.startTime.isFinite && command.endTime.isFinite)
            }
        }
    }

    /// Random shuffles units: all glyphs of a word keep one delay, and the
    /// delays are a permutation of the word ranks.
    @Test("Random with Word shuffles whole words")
    func randomWords() {
        let a = arrivals(sprites(
            "aa bb cc dd ee",
            [P.stagger: .number(100), P.unit: .choice("Word"), P.staggerFrom: .choice("Random")],
        ))
        for word in 0..<5 {
            #expect(a[word * 2] == a[word * 2 + 1])
        }
        let perWord = (0..<5).map { a[$0 * 2] }
        #expect(perWord.sorted() == [0, 100, 200, 300, 400])
    }

    // ─── Descriptor ──────────────────────────────────────────────────────────

    private func visible(_ values: [String: EffectValue]) -> Set<String> {
        let all = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        return Set(TextEffect.descriptor.parameters.filter { $0.shownWhen?.holds(in: all) ?? true }.map(\.id))
    }

    /// S3.4, S9.1, S9.2, S9.5
    @Test("conditional parameters follow Order and Stagger Mode")
    func visibility() {
        for order in ["Start", "End", "Centre", "Random", "Edges", "Wave"] {
            for mode in ["Per Unit", "Spread"] {
                let shown = visible([P.staggerFrom: .choice(order), P.staggerMode: .choice(mode)])
                #expect(shown.contains(P.waveAmount) == (order == "Wave"), "\(order)/\(mode)")
                #expect(shown.contains(P.stagger) == (mode == "Per Unit"), "\(order)/\(mode)")
                #expect(shown.contains(P.staggerSpread) == (mode == "Spread"), "\(order)/\(mode)")
                #expect(shown.contains(P.unit) && shown.contains(P.staggerMode))
            }
        }
    }

    /// S9.6 for the parameters this slice adds: each one, with its condition
    /// met, changes the evaluated output.
    @Test("each new parameter changes the output")
    func everyParameterMatters() {
        func signature(_ values: [String: EffectValue]) -> [String] {
            // Commands only: every placement mints a fresh node id, and the
            // sprite ids that carry it would make any two runs "differ".
            sprites("ab cd\nef gh", values).map { String(reflecting: $0.commands) }
        }
        let base: [String: EffectValue] = [P.stagger: .number(100), P.fadeOut: .number(300)]
        let plain = signature(base)

        #expect(signature(base.merging([P.unit: .choice("Word")]) { $1 }) != plain)

        let wave: [String: EffectValue] = base.merging([P.staggerFrom: .choice("Wave")]) { $1 }
        #expect(signature(wave) != plain)
        #expect(signature(wave.merging([P.waveAmount: .number(2.5)]) { $1 }) != signature(wave))

        let spread: [String: EffectValue] = base.merging([P.staggerMode: .choice("Spread")]) { $1 }
        #expect(signature(spread) != plain)
        #expect(signature(spread.merging([P.staggerSpread: .number(20)]) { $1 }) != signature(spread))
    }

    // ─── Inspector groups ────────────────────────────────────────────────────

    /// S9.3: the order the inspector shows, straight from the descriptor —
    /// the inspector has no text-specific code, so this is the whole layout.
    @Test("the parameters fall into the inspector's groups")
    func groups() {
        let descriptor = TextEffect.descriptor
        #expect(descriptor.groups == [
            "Content", "Layout", "Colour", "Sequence", "Entrance", "Scatter", "Hold", "Exit",
        ])
        func members(_ group: String) -> [String] {
            descriptor.parameters.filter { $0.group == group }.map(\.id)
        }
        #expect(members("Colour") == [
            P.color, P.additive, P.colourMode, P.colour2, P.gradientAcross,
            P.sweepOrder, P.sweepStart, P.sweepLength, P.sweepEdge, P.flash,
        ])
        #expect(members("Sequence") == [
            P.unit, P.staggerFrom, P.waveAmount, P.staggerMode, P.stagger, P.staggerSpread,
        ])
        #expect(members("Entrance") == [
            P.fadeIn, P.easing, P.riseFrom, P.driftFrom, P.scaleFrom, P.spinFrom,
            P.stretchFromX, P.stretchFromY, P.pivot,
        ])
        #expect(members("Scatter") == [P.scatterX, P.scatterY, P.scatterRotation, P.scatterScale])
        #expect(members("Hold") == [
            P.driftX, P.driftY, P.holdMotion, P.holdAmount, P.holdBreathe, P.holdSpeed, P.holdPhase,
        ])
        #expect(members("Exit") == [
            P.fadeOut, P.exit, P.exitForce, P.exitStagger, P.exitOrder,
            P.outRise, P.outDrift, P.outScale, P.outSpin, P.outStretchX, P.outStretchY,
            P.outScatter, P.outScatterRotation, P.outEasing,
        ])
    }

    /// A hold control that does nothing under the chosen motion is hidden:
    /// Amount moves, Breathe swells, Phase Spread offsets a cycle.
    @Test("hold controls show only for the motions they drive")
    func holdVisibility() {
        let expected: [String: Set<String>] = [
            "None": [],
            "Wave": [P.holdAmount, P.holdSpeed, P.holdPhase],
            "Float": [P.holdAmount, P.holdSpeed, P.holdPhase],
            "Jitter": [P.holdAmount, P.holdSpeed],
            "Shake": [P.holdAmount, P.holdSpeed],
            "Breathe": [P.holdBreathe, P.holdSpeed, P.holdPhase],
        ]
        let controls: Set<String> = [P.holdAmount, P.holdBreathe, P.holdSpeed, P.holdPhase]
        for (motion, shown) in expected {
            #expect(visible([P.holdMotion: .choice(motion)]).intersection(controls) == shown, "\(motion)")
        }
    }

    /// The colour controls follow the mode the same way.
    @Test("colour controls show only for the mode they drive")
    func colourVisibility() {
        let controls: Set<String> = [
            P.colour2, P.gradientAcross, P.sweepOrder, P.sweepStart, P.sweepLength, P.sweepEdge, P.flash,
        ]
        let expected: [String: Set<String>] = [
            "Solid": [],
            "Gradient": [P.colour2, P.gradientAcross],
            "Highlight": [P.colour2, P.sweepOrder, P.sweepStart, P.sweepLength, P.sweepEdge, P.flash],
        ]
        for (mode, shown) in expected {
            #expect(visible([P.colourMode: .choice(mode)]).intersection(controls) == shown, "\(mode)")
        }
    }

    /// Exit Force is how far Explode and Drift throw; under any other exit it
    /// is a control that does nothing.
    @Test("Exit Force shows only for the exits that throw")
    func exitForceVisibility() {
        for exit in ["Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift"] {
            let shown = visible([P.exit: .choice(exit)])
            #expect(shown.contains(P.exitForce) == ["Explode", "Drift"].contains(exit), "\(exit)")
        }
    }

    /// S9.4: whatever the conditions, no group is left as an empty heading.
    @Test("no group is ever empty")
    func noEmptyGroup() {
        for order in ["Start", "Wave"] {
            for mode in ["Per Unit", "Spread"] {
                for exit in ["Fade", "Explode"] {
                    let shown = visible([
                        P.staggerFrom: .choice(order), P.staggerMode: .choice(mode), P.exit: .choice(exit),
                    ])
                    for group in TextEffect.descriptor.groups {
                        #expect(TextEffect.descriptor.parameters.contains { $0.group == group && shown.contains($0.id) })
                    }
                }
            }
        }
    }
}
