import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// Declaring a control, showing it, and reading it back.
///
/// `params()` was a no-op, so a script could declare controls and nothing read
/// them: the inspector had nothing to draw and `param(id)` always fell back to
/// a default. Declared and unreachable is the worst of the three states — it
/// looks like the feature is there.
@Suite("Script parameters", .serialized)
struct ScriptParamsTests {
    private func run(
        _ source: String,
        values: [String: EffectValue] = [:],
    ) -> ScriptRuntime.Outcome {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: values, duration: 4000, seed: 1,
        ))
    }

    // MARK: - Declaring

    @Test("a declaration becomes a parameter")
    func declarationBecomesParameter() throws {
        let outcome = run("""
        params({ count: { type: 'integer', default: 24 } })
        sprite(Image.soft)
        """)

        let declared = try #require(outcome.declared)
        #expect(declared.count == 1)
        #expect(declared.first?.id == "count")
        #expect(declared.first?.defaultValue == .integer(24))
    }

    /// The label comes for free, titled like every other parameter in the app.
    @Test("the id becomes a title without being written twice")
    func idBecomesTitle() throws {
        let declared = try #require(run("""
        params({ count: { type: 'integer', default: 1 } })
        """).declared)

        #expect(declared.first?.name == "Count")
    }

    @Test("a given name wins over the id")
    func givenNameWins() throws {
        let declared = try #require(run("""
        params({ count: { type: 'integer', default: 1, name: 'How many' } })
        """).declared)

        #expect(declared.first?.name == "How many")
    }

    @Test("every kind is declarable", arguments: [
        ("{ type: 'number', default: 1.5 }", EffectValue.number(1.5)),
        ("{ type: 'integer', default: 7 }", .integer(7)),
        ("{ type: 'toggle', default: true }", .toggle(true)),
        ("{ type: 'text', default: 'sb/a.png' }", .text("sb/a.png")),
        ("{ type: 'choice', default: 'ring', options: ['ring', 'disc'] }", .choice("ring")),
    ])
    func kindsAreDeclarable(declaration: String, expected: EffectValue) throws {
        let declared = try #require(run("params({ p: \(declaration) })").declared)

        #expect(declared.first?.defaultValue == expected)
    }

    /// The form somebody writes a colour in.
    @Test("a colour is read from hex", arguments: [
        ("'#ff8844'", EffectColor(r: 255, g: 136, b: 68)),
        ("'ff8844'", EffectColor(r: 255, g: 136, b: 68)),
        ("'#f84'", EffectColor(r: 255, g: 136, b: 68)),
    ])
    func colourFromHex(literal: String, expected: EffectColor) throws {
        let declared = try #require(
            run("params({ tint: { type: 'color', default: \(literal) } })").declared,
        )

        #expect(declared.first?.defaultValue == .color(expected))
    }

    /// A range means a slider, which is what a range is for.
    @Test("a range becomes a slider")
    func rangeBecomesSlider() throws {
        let declared = try #require(run("""
        params({ count: { type: 'integer', default: 24, range: [1, 200] } })
        """).declared)

        #expect(declared.first?.range == 1...200)
        #expect(declared.first?.presentation == .slider)
    }

    @Test("no range means a field")
    func noRangeMeansField() throws {
        let declared = try #require(run("""
        params({ count: { type: 'integer', default: 24 } })
        """).declared)

        #expect(declared.first?.presentation == .field)
    }

    /// Declaration order, which is the order they appear in the inspector.
    @Test("declaration order is kept")
    func orderIsKept() throws {
        let declared = try #require(run("""
        params({
          zebra: { type: 'number', default: 1 },
          apple: { type: 'number', default: 2 },
        })
        """).declared)

        #expect(declared.map(\.id) == ["zebra", "apple"])
    }

    // MARK: - What must not be declared

    /// A declaration missing its type is skipped rather than guessed at: a
    /// control drawn as the wrong kind reads the wrong value back.
    @Test("an incomplete declaration is skipped", arguments: [
        "params({ p: { default: 1 } })",
        "params({ p: { type: 'nonsense', default: 1 } })",
        "params({ p: 24 })",
    ])
    func incompleteIsSkipped(source: String) throws {
        let declared = try #require(run(source).declared)

        #expect(declared.isEmpty, "\(source) produced a parameter")
    }

    /// A script that never declares reports `nil`, not an empty list.
    ///
    /// The difference matters: nothing declared should leave whatever the
    /// inspector had, not clear it.
    @Test("no params call reports nothing rather than nothing declared")
    func noCallReportsNil() {
        #expect(run("sprite(Image.soft)").declared == nil)
    }

    // MARK: - Reading back

    /// The whole point: what the inspector holds is what the script reads.
    @Test("param reads the stored value, not the default")
    func paramReadsStoredValue() {
        let outcome = run(
            """
            params({ count: { type: 'integer', default: 5 } })
            for (let i = 0; i < param('count'); i++) sprite(Image.soft)
            """,
            values: ["count": .integer(3)],
        )

        #expect(outcome.sprites.count == 3, "it used the default instead of the stored value")
    }

    /// A freshly placed clip has a declaration and no stored values yet.
    ///
    /// The inspector fills those in on the next pass, so `param()` has to
    /// answer from the declaration in the meantime — it returned 0, and the
    /// starter template drew nothing at all. Caught by the test asserting the
    /// template draws, which is the claim that test exists to make.
    @Test("a declared default answers before anything is stored")
    func declaredDefaultAnswers() {
        let outcome = run("""
        params({ count: { type: 'integer', default: 3 } })
        for (let i = 0; i < param('count'); i++) sprite(Image.soft)
        """)

        #expect(outcome.sprites.count == 3, "the declared default did not answer")
    }

    /// And a stored value still wins over it.
    @Test("a stored value beats the declared default")
    func storedBeatsDeclared() {
        let outcome = run(
            """
            params({ count: { type: 'integer', default: 3 } })
            for (let i = 0; i < param('count'); i++) sprite(Image.soft)
            """,
            values: ["count": .integer(5)],
        )

        #expect(outcome.sprites.count == 5)
    }

    /// A colour reads the same whether it came from the inspector or its own
    /// declaration — two conversions is how one path gives channels and the
    /// other gives a string.
    @Test("a declared colour default arrives as channels")
    func declaredColourIsChannels() {
        let outcome = run("""
        params({ tint: { type: 'color', default: '#ff8844' } })
        const c = param('tint')
        if (c.r !== 255 || c.g !== 136 || c.b !== 68) {
            throw new Error('got ' + JSON.stringify(c))
        }
        sprite(Image.soft)
        """)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    @Test("every kind reads back", arguments: [
        ("number", EffectValue.number(2.5), "2.5"),
        ("integer", .integer(7), "7"),
        ("toggle", .toggle(true), "true"),
        ("text", .text("hello"), "hello"),
    ])
    func kindsReadBack(type: String, stored: EffectValue, expected: String) {
        let outcome = run(
            """
            params({ p: { type: '\(type)', default: 0 } })
            if (String(param('p')) !== '\(expected)') {
                throw new Error('got ' + String(param('p')))
            }
            sprite(Image.soft)
            """,
            values: ["p": stored],
        )

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// A colour arrives as something a script can use.
    @Test("a colour reads back as channels")
    func colourReadsBack() {
        let outcome = run(
            """
            const c = param('tint')
            if (c.r !== 255 || c.g !== 136 || c.b !== 68) {
                throw new Error('got ' + JSON.stringify(c))
            }
            sprite(Image.soft)
            """,
            values: ["tint": .color(EffectColor(r: 255, g: 136, b: 68))],
        )

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }
}
