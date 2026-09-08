import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// Stopping a script that never stops.
///
/// JavaScriptCore cannot interrupt a tight loop from the same thread, and the
/// API that could — `JSContextGroupSetExecutionTimeLimit` — is private WebKit,
/// absent from the public macOS SDK. So the loop is made to stop itself: a
/// counter goes into every loop body at compile time, and past a ceiling the
/// script throws. Throwing is something JavaScript can do on its own, so
/// nothing has to be interrupted from outside.
@Suite("Loop instrumentation")
struct LoopInstrumentationTests {
    private func run(_ source: String, seed: UInt64 = 42) -> ScriptRuntime.Outcome {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: seed,
        ))
    }

    /// Every loop form, because a missed one is a hole.
    ///
    /// Parameterised rather than written once for `for`: the instrumenter
    /// rewrites source, and a form it does not recognise passes straight
    /// through uncounted — which is exactly the case somebody would hit.
    @Test("an endless loop is stopped", arguments: [
        "while (true) { }",
        "for (;;) { }",
        "do { } while (true)",
        "for (let i = 0; i >= 0; i++) { }",
        "while (1) { let x = 1 }",
        "outer: while (true) { continue outer }",
    ])
    func endlessLoopsAreStopped(source: String) {
        let started = Date()
        let outcome = run(source)
        let elapsed = Date().timeIntervalSince(started)

        // Generous on purpose. The distinction being tested is "stops" versus
        // "never stops" — an unguarded runaway has no finish time at all — and a
        // tight bound turns a machine under load into a red test, which teaches
        // people to ignore red tests. Measured at ~20ms unloaded.
        #expect(elapsed < 30, "took \(Int(elapsed * 1000))ms — it did not stop on its own")
        #expect(!outcome.diagnostics.isEmpty, "\(source) ran to completion, which it cannot have")
    }

    /// The budget is shared across loops, not counted per loop.
    ///
    /// Per-loop counters are defeated by nesting: two loops of two thousand
    /// each stay under any per-loop ceiling while running four million times
    /// between them. This is the test that pins the choice, and it must fail if
    /// anyone later switches to per-loop counting.
    @Test("nested loops share one budget")
    func nestedLoopsShareTheBudget() {
        let outcome = run("""
        let n = 0
        for (let a = 0; a < 2000; a++) {
            for (let b = 0; b < 2000; b++) { n++ }
        }
        sprite(Image.soft)
        """)

        #expect(!outcome.diagnostics.isEmpty, "four million iterations ran without hitting the ceiling")
        #expect(outcome.sprites.isEmpty)
    }

    /// A legitimate loop has to finish.
    ///
    /// The ceiling exists to stop a runaway, and a script that emits the two
    /// thousand sprites the clamp allows is not one — a guard that stops honest
    /// work is worse than no guard, because it makes the tool unusable rather
    /// than merely unsafe.
    @Test("a legitimate loop over the sprite ceiling completes")
    func legitimateLoopCompletes() {
        let outcome = run("""
        for (let i = 0; i < \(ScriptLimits.maximumSprites); i++) {
            sprite(Image.soft).fade(0, 100, 0, 1)
        }
        """)

        #expect(outcome.sprites.count == ScriptLimits.maximumSprites)
        #expect(outcome.diagnostics.isEmpty)
    }

    /// Counting must not change what a script draws.
    ///
    /// The instrumenter rewrites source, so the risk is not that it fails to
    /// stop a runaway — it is that it quietly changes a working script. Read
    /// from the evaluated output, because that is the only thing that says the
    /// rewrite was transparent.
    @Test("instrumentation does not change a terminating script's output")
    func instrumentationIsTransparent() {
        let source = """
        for (let i = 0; i < 20; i++) {
            sprite(Image.soft).move(0, 1000, i * 10, i * 5, 320, 240)
        }
        """

        let instrumented = run(source)
        let bare = ScriptEngine(instrumentsLoops: false).run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: 42,
        ))

        #expect(instrumented.sprites.count == 20)
        #expect(signature(instrumented) == signature(bare))
    }

    /// Loop bodies without braces are rewritten too.
    ///
    /// `while (x) doThing()` is legal, and a rewrite that only handles braced
    /// bodies would either miss it or corrupt it.
    @Test("a braceless loop body still counts")
    func bracelessBodyCounts() {
        let started = Date()
        let outcome = run("let n = 0; while (true) n++")

        #expect(Date().timeIntervalSince(started) < 30)
        #expect(!outcome.diagnostics.isEmpty)
    }

    private func signature(_ outcome: ScriptRuntime.Outcome) -> String {
        outcome.sprites.map { sprite in
            let commands = sprite.commands.map { command -> String in
                if case let .move(a, b, c, d) = command.payload {
                    return "M:\(a),\(b),\(c),\(d)"
                }
                return "\(command.kind.rawValue)"
            }.joined(separator: "|")
            return "\(sprite.id);\(commands)"
        }.joined(separator: "\n")
    }
}
