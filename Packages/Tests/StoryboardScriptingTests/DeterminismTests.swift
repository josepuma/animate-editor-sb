import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// Two evaluations of the same script must agree, exactly.
///
/// The whole architecture rests on this. The preview and the exported `.osb`
/// are two evaluations of one document, so a script that answers differently
/// each time ships a file nobody looked at. `EditHistory` restores documents
/// on the same assumption: undo puts back what was stored, and if evaluating
/// that produced something new, undo would land somewhere the author never was.
///
/// So the interesting tests here are not "is it deterministic" — they are the
/// bypasses. A lock nobody tried to pick is a lock nobody knows the strength
/// of, and each case below is a real one-liner that defeats a naive
/// implementation.
@Suite("Script determinism")
struct DeterminismTests {
    private func request(_ source: String, seed: UInt64 = 42) -> ScriptRuntime.Request {
        ScriptRuntime.Request(
            nodeID: "fx",
            idPrefix: "fx",
            source: source,
            values: [:],
            duration: 4000,
            seed: seed,
        )
    }

    /// A fingerprint of what the renderer would draw.
    ///
    /// Read from the produced sprites rather than by re-deriving the seed
    /// stream: a test that reimplements its subject's formula agrees with any
    /// formula, including a wrong one.
    /// The payload is part of the fingerprint, not just the timing.
    ///
    /// The first version recorded only kind and times, which every one of these
    /// scripts produces identically — so it compared two runs that differed in
    /// every number and called them equal. The seed tests passed a broken
    /// signature and failed a working generator, which is the wrong way round
    /// twice over.
    private func signature(_ outcome: ScriptRuntime.Outcome) -> String {
        outcome.sprites.map { sprite in
            let commands = sprite.commands.map {
                "\($0.kind.rawValue):\($0.timing.startTime):\($0.timing.endTime):\(payload($0))"
            }.joined(separator: "|")
            return "\(sprite.id);\(sprite.filePath);\(sprite.defaultX);\(sprite.defaultY);\(commands)"
        }.joined(separator: "\n")
    }

    private func payload(_ command: Command) -> String {
        switch command.payload {
        case let .fade(a, b): "\(a),\(b)"
        case let .move(a, b, c, d): "\(a),\(b),\(c),\(d)"
        case let .moveX(a, b): "\(a),\(b)"
        case let .moveY(a, b): "\(a),\(b)"
        case let .scale(a, b): "\(a),\(b)"
        case let .vectorScale(a, b, c, d): "\(a),\(b),\(c),\(d)"
        case let .rotate(a, b): "\(a),\(b)"
        case let .color(a, b, c, d, e, f): "\(a),\(b),\(c),\(d),\(e),\(f)"
        case let .parameter(kind): kind.rawValue
        }
    }

    private func run(_ source: String, seed: UInt64 = 42) -> ScriptRuntime.Outcome {
        ScriptEngine().run(request(source, seed: seed))
    }

    /// Every way a script might reach for a number that changes between runs.
    ///
    /// Each of these defeats a plain `Math.random = …` assignment, which is why
    /// the lock uses `defineProperty` with `writable: false, configurable:
    /// false` — measured against a real `JSContext`, not assumed.
    /// Each of these must be *observably* the seeded stream, not merely
    /// deterministic.
    ///
    /// The first version wrapped the attacks in `try/catch` with a fallback, so
    /// a script whose reassignment *succeeded* still produced a repeatable
    /// number — the suite went green with the lock deliberately weakened to a
    /// plain assignment, which is the one outcome that makes it worthless.
    ///
    /// So the assertion is against a reference run instead: whatever route a
    /// script takes to `Math.random`, it has to land on the same value the
    /// plain call gives. A successful reassignment returns something else and
    /// fails, which is the whole point.
    static let bypasses = [
        // The straightforward call — the reference.
        "Math.random()",
        // Reaching for the original through a fresh function object.
        "Function('return Math.random')()()",
        // The same, through eval.
        "eval('Math.random()')",
        // Overwriting the lock, then calling it. Uncaught on purpose: a lock
        // that throws here is a lock working, and one that silently accepts the
        // write has to show up as a different number.
        "(function () { try { Math.random = function () { return 0.123456789 } } catch (e) {} return Math.random() })()",
        // Deleting the lock so the engine's own generator shows through.
        "(function () { try { delete Math.random } catch (e) {} return typeof Math.random === 'function' ? Math.random() : -1 })()",
        // Through a getter defined on top of it.
        "(function () { try { Object.defineProperty(Math, 'random', { value: function () { return 0.987654321 } }) } catch (e) {} return Math.random() })()",
    ]

    @Test("every route to Math.random lands on the seeded stream", arguments: bypasses)
    func bypassesAreClosed(expression: String) {
        // A context whose very first call is the plain one, for the value the
        // seeded stream is meant to start at.
        let reference = firstNumber(from: "Math.random()")
        let reached = firstNumber(from: expression)

        #expect(reference != nil, "the reference run produced no number")
        #expect(reached == reference, "\(expression) reached a different generator")
    }

    /// The first number a fresh context yields for `expression`.
    ///
    /// Read out through a sprite's position, because that is what a script can
    /// actually affect — and reading the evaluated output is the only way to
    /// know the value the storyboard would be built from.
    private func firstNumber(from expression: String) -> Double? {
        let outcome = run("sprite(Image.soft).move(0, 1000, (\(expression)) * 1000, 0, 0, 0)")
        guard case let .move(startX, _, _, _) = outcome.sprites.first?.commands.first?.payload else {
            return nil
        }
        return startX
    }

    /// Two contexts, not two calls in one.
    ///
    /// A fresh `JSContext` per invocation is the design, so agreement within
    /// one context proves less than it looks: the seeded stream has to restart
    /// from the same place every time a context is built.
    @Test("two separately built contexts agree")
    func separateContextsAgree() {
        let source = "for (let i = 0; i < 20; i++) sprite(Image.soft).move(0, 1000, rng.between(0, 640), 0, 0, 0)"

        #expect(signature(ScriptEngine().run(request(source))) == signature(ScriptEngine().run(request(source))))
    }

    /// The clock is a source of fresh numbers too, and the constraint that
    /// named `Math.random` did not name it.
    @Test("the clock is not reachable", arguments: [
        "typeof Date",
        "typeof performance",
        "typeof crypto",
    ])
    func clockIsAbsent(expression: String) {
        let outcome = run("if (\(expression) !== 'undefined') { throw new Error('\(expression) is reachable') } sprite(Image.soft)")

        #expect(outcome.diagnostics.isEmpty, "\(expression) is still reachable")
        #expect(outcome.sprites.count == 1)
    }

    /// A different seed has to give a different field, or the seed is decoration.
    @Test("changing the seed changes the result")
    func seedMatters() {
        let source = "for (let i = 0; i < 20; i++) sprite(Image.soft).move(0, 1000, rng.between(0, 640), 0, 0, 0)"

        #expect(signature(run(source, seed: 1)) != signature(run(source, seed: 2)))
    }

    /// Adjacent seeds, specifically.
    ///
    /// Nobody jumps from 8371 to 99123 — they nudge the field by one. This
    /// codebase has already been bitten by deriving a stream by *adding* to a
    /// seed, where SplitMix64 swallowed the difference and changing the seed
    /// appeared to do nothing.
    @Test("adjacent seeds give different fields")
    func adjacentSeedsDiffer() {
        let source = "for (let i = 0; i < 20; i++) sprite(Image.soft).move(0, 1000, rng.between(0, 640), 0, 0, 0)"

        #expect(signature(run(source, seed: 8371)) != signature(run(source, seed: 8372)))
    }

    /// The global object holds what was installed and nothing else.
    ///
    /// Asserted as equality rather than "contains none of a blocklist": a
    /// blocklist only catches what somebody thought to list, and the point of
    /// building the context by adding is that anything not added is absent.
    @Test("the global object holds only what was installed")
    func globalIsExactlyTheAllowList() {
        let outcome = run("""
        const names = Object.getOwnPropertyNames(globalThis).sort().join(',')
        if (names !== '\(ScriptEngine.allowedGlobals.sorted().joined(separator: ","))') {
            throw new Error('globals are ' + names)
        }
        sprite(Image.soft)
        """)

        #expect(outcome.diagnostics.isEmpty)
    }

    /// Nothing that reads or writes the outside world is reachable.
    @Test("the host is not reachable", arguments: [
        "typeof require",
        "typeof fetch",
        "typeof XMLHttpRequest",
        "typeof process",
        "typeof WebAssembly",
        "typeof globalThis.window",
    ])
    func hostIsAbsent(expression: String) {
        let outcome = run("if (\(expression) !== 'undefined') { throw new Error('reachable') } sprite(Image.soft)")

        #expect(outcome.diagnostics.isEmpty, "\(expression) is reachable from a script")
    }
}
