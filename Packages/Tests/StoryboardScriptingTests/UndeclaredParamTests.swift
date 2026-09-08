import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// Reading a control that was never declared.
///
/// `param('cout')` — a typo — returned `undefined` silently, and `undefined *
/// 2` is NaN: a script reading a control it forgot to declare drew nothing
/// with nothing to say why. Reported as exactly that confusion, by somebody
/// who wrote `param('count')` expecting a control to appear.
@Suite("Undeclared parameters", .serialized)
struct UndeclaredParamTests {
    private func run(_ source: String, values: [String: EffectValue] = [:]) -> ScriptRuntime.Outcome {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: values, duration: 4000, seed: 1,
        ))
    }

    @Test("reading an undeclared control is reported")
    func undeclaredIsReported() {
        let outcome = run("const c = param('count'); sprite(Image.soft)")

        #expect(!outcome.diagnostics.isEmpty, "it read a control that does not exist, silently")
    }

    /// The message names the id, because a typo is only obvious once you see
    /// what you typed.
    @Test("the message names what was read")
    func messageNamesTheId() throws {
        let outcome = run("param('cout'); sprite(Image.soft)")
        let diagnostic = try #require(outcome.diagnostics.first)

        guard case let .runtimeFailed(message) = diagnostic else {
            Issue.record("not a runtime failure")
            return
        }
        #expect(message.contains("'cout'"))
        #expect(message.contains("params()"), "it should say how to fix it")
    }

    /// Declared is silent, which is the whole point.
    @Test("a declared control is not reported")
    func declaredIsSilent() {
        let outcome = run("""
        params({ count: { type: 'integer', default: 24 } })
        const c = param('count')
        sprite(Image.soft)
        """)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// A stored value counts as declared enough: the inspector has it, so
    /// there is a control — this is a script whose declaration was removed
    /// while its values remain.
    @Test("a stored value is not reported")
    func storedIsSilent() {
        let outcome = run(
            "const c = param('count'); sprite(Image.soft)",
            values: ["count": .integer(5)],
        )

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// Every id is named, not just the first.
    @Test("several unknown ids are all named")
    func severalAreNamed() throws {
        let outcome = run("param('a'); param('b'); sprite(Image.soft)")
        let diagnostic = try #require(outcome.diagnostics.first)

        guard case let .runtimeFailed(message) = diagnostic else {
            Issue.record("not a runtime failure")
            return
        }
        #expect(message.contains("'a'"))
        #expect(message.contains("'b'"))
    }

    /// Reported once however many times it is read: the same id in a loop is
    /// one mistake, not two thousand.
    @Test("one id read repeatedly is reported once")
    func reportedOnce() {
        let outcome = run("""
        for (let i = 0; i < 50; i++) param('count')
        sprite(Image.soft)
        """)

        #expect(outcome.diagnostics.count == 1)
    }

    /// The sprites survive. A missing declaration is worth saying and not
    /// worth throwing away a clip over — the script may well draw correctly
    /// with its fallback.
    @Test("the clip still draws")
    func clipStillDraws() {
        let outcome = run("""
        const count = param('count') ?? 3
        for (let i = 0; i < count; i++) sprite(Image.soft)
        """)

        #expect(outcome.sprites.count == 3)
        #expect(!outcome.diagnostics.isEmpty, "and it still says the control is missing")
    }
}
