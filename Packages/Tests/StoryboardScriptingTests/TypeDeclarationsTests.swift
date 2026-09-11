import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// The type declarations an external editor reads.
///
/// Generated from the tables the engine installs, never written by hand. This
/// project has already shipped the hand-written version of this: the
/// completion table carried all thirty-five easing names **backwards**
/// (`outQuad` where the enum says `quadOut`), so a name the runtime rejects
/// arrived as `undefined`, became NaN, was clamped to zero — and zero is
/// `linear`. A script animated wrongly, in silence, in a saved project.
///
/// So the guards below are about **agreement**, not about content: every name
/// the engine installs has to appear, and nothing may appear that the engine
/// does not install.
@Suite("Type declarations")
struct TypeDeclarationsTests {
    /// Every easing the runtime accepts is declared, by its runtime name.
    @Test("every easing is declared", arguments: Easing.allCases)
    func everyEasingIsDeclared(_ easing: Easing) {
        let name = EaseConstants.table.first { $0.value == easing.rawValue }?.key

        #expect(
            TypeDeclarations.text.contains("readonly \(try! #require(name)):"),
            "Ease.\(name ?? "?") is callable but undeclared, so the editor would not offer it",
        )
    }

    /// Nothing is declared under `Ease` that the runtime does not know.
    ///
    /// The direction that actually caught the historical bug: a declared name
    /// the runtime rejects is offered by autocompletion and then silently
    /// becomes `linear`.
    @Test("no easing is declared that the runtime rejects")
    func noInventedEasings() throws {
        let declared = try names(inBlock: "Ease")

        #expect(!declared.isEmpty, "the block has to have been found, or this asserts nothing")
        #expect(
            declared.allSatisfy { EaseConstants.table.keys.contains($0) },
            "declared but unknown: \(declared.filter { !EaseConstants.table.keys.contains($0) })",
        )
    }

    /// Every built-in image is declared, and no others.
    @Test("the image table round-trips")
    func imageTableRoundTrips() throws {
        let declared = try names(inBlock: "Image")

        #expect(Set(declared) == Set(ImageConstants.table.keys))
    }

    /// Every layer and origin the format has is declared.
    @Test("layers and origins round-trip")
    func layersAndOriginsRoundTrip() throws {
        #expect(try Set(names(inBlock: "Layer")) == Set(LayerConstants.table.keys))
        #expect(try Set(names(inBlock: "Origin")) == Set(LayerConstants.originTable.keys))
    }

    /// Every chaining method is declared on the builder.
    @Test("every sprite method is declared", arguments: SpriteMethod.allCases)
    func everySpriteMethodIsDeclared(_ method: SpriteMethod) {
        #expect(
            TypeDeclarations.text.contains("\(method.rawValue)("),
            ".\(method.rawValue)() is callable but undeclared",
        )
    }

    /// Every storyboard global the engine allows is declared.
    ///
    /// Filtered to the API rather than the language: `Array` and `Math` come
    /// from JavaScriptCore and are already in the editor's own lib.
    @Test("every storyboard global is declared")
    func everyGlobalIsDeclared() {
        let api = ["Ease", "Image", "Layer", "Origin", "duration", "param", "params", "rng", "sprite"]

        for name in api {
            #expect(
                TypeDeclarations.text.contains("declare const \(name)")
                    || TypeDeclarations.text.contains("declare function \(name)"),
                "\(name) is installed by the engine but not declared",
            )
        }
    }

    /// The guard against the loop counter leaking into the editor.
    ///
    /// `__tick` and `__ticks` are installed, and deliberately visible to the
    /// script — but they are the instrumenter's, not the author's. Declaring
    /// them would offer them in autocompletion as though they were API.
    @Test("the loop guard is not declared as API")
    func loopGuardIsNotDeclared() {
        #expect(!TypeDeclarations.text.contains("declare function __tick"))
        #expect(!TypeDeclarations.text.contains("declare const __ticks"))
    }

    /// The config is what makes any of this reach the editor.
    ///
    /// Measured: without a `jsconfig.json` the declarations are silently
    /// ignored while autocompletion still *appears* to work, offering
    /// identifiers scraped from the file's own text. And `dom` has to be out,
    /// or our `Image` resolves to the browser's `HTMLImageElement`.
    @Test("the config excludes the DOM")
    func configExcludesTheDOM() {
        let config = TypeDeclarations.configuration

        #expect(config.contains("\"checkJs\""), "checking is the point of shipping types")
        #expect(config.contains("\"lib\""), "an unconstrained lib pulls in the DOM")
        #expect(!config.lowercased().contains("\"dom\""), "our Image would resolve to HTMLImageElement")
    }

    /// Each script is its own scope.
    ///
    /// A `.js` with no import or export is a **script**, not a module, so
    /// every one in the folder shares a single global scope: a second clip
    /// declaring `const count` was flagged as redeclaring the first one's,
    /// pointing at a file the author is not even editing. Reported from a real
    /// project, and measured — two files each declaring `count` give the error
    /// without this and nothing with it, while the four deliberate mistakes
    /// are still caught either way.
    @Test("each script gets its own scope")
    func eachScriptIsItsOwnScope() {
        let config = TypeDeclarations.configuration

        #expect(config.contains("\"moduleDetection\": \"force\""))
        #expect(config.contains("\"module\""), "moduleDetection needs a module system to name")
    }

    /// Regenerating writes the same bytes, so staleness heals itself.
    @Test("generation is idempotent")
    func generationIsIdempotent() {
        #expect(TypeDeclarations.text == TypeDeclarations.text)
        #expect(TypeDeclarations.configuration == TypeDeclarations.configuration)
    }

    /// Both files say they are generated.
    @Test("generated files say so")
    func generatedFilesSaySo() {
        #expect(TypeDeclarations.text.contains("Generated"))
    }

    /// A timed method accepts its call with the easing and without it.
    ///
    /// Declared as one signature with `easing?: number` ahead of the required
    /// parameters, TypeScript rejects **every correct call**: an optional
    /// cannot precede required ones, so `.move(Ease.quadOut, 0, 900, …)` came
    /// back as "Expected 5 arguments, but got 4" — the declarations flagging
    /// valid code, which is worse than declaring nothing because it teaches
    /// the author to switch checking off. Two overloads say the same thing.
    ///
    /// Caught by running the generated file through the TypeScript compiler,
    /// not by reading it. This guard pins the shape so it cannot regress.
    @Test("a timed method declares both spellings", arguments: SpriteMethod.allCases.filter(\.isTimed))
    func timedMethodsDeclareBothSpellings(_ method: SpriteMethod) {
        let text = TypeDeclarations.text
        let timed = "\(method.rawValue)(startTime: number, endTime: number"
        let eased = "\(method.rawValue)(easing: number, startTime: number, endTime: number"

        #expect(text.contains(timed), "the no-easing spelling has to be declared")
        #expect(text.contains(eased), "the with-easing spelling has to be declared")
        #expect(
            !text.contains("\(method.rawValue)(easing?:"),
            "an optional before required parameters rejects every correct call",
        )
    }

    // MARK: -

    /// The keys declared inside `declare const <name>: { … }`.
    private func names(inBlock block: String) throws -> [String] {
        let text = TypeDeclarations.text
        let opening = try #require(
            text.range(of: "declare const \(block): {"),
            "no `\(block)` block — a guard that cannot find its subject asserts nothing",
        )
        let closing = try #require(text.range(of: "\n}", range: opening.upperBound ..< text.endIndex))
        let body = text[opening.upperBound ..< closing.lowerBound]

        return body
            .split(separator: "\n")
            .compactMap { line in
                guard let start = line.range(of: "readonly ") else { return nil }
                guard let colon = line.range(of: ":", range: start.upperBound ..< line.endIndex) else {
                    return nil
                }
                return String(line[start.upperBound ..< colon.lowerBound])
            }
    }

    /// Every `type` the declarations offer is one the runtime accepts, and every
    /// one it accepts is offered.
    ///
    /// Not a comparison against a second list — that agrees with any list. Each
    /// name is *run through the engine*, and a declaration counts only if the
    /// parameter comes back declared.
    ///
    /// This caught the block spelling three things wrong at once: it offered
    /// `'boolean'`, which the runtime drops (the case is `toggle`), and left out
    /// `'text'`, which the runtime takes. The first is the worse half — a script
    /// writing `'boolean'` type-checks clean and the parameter silently does not
    /// exist, with no diagnostic, which is the backwards-easing failure again.
    @Test("the declared parameter types are the ones the runtime accepts", arguments: EffectParameter.Kind.allCases)
    func parameterKindsMatchRuntime(kind: EffectParameter.Kind) {
        // A motion path is drawn on the canvas, so a script cannot declare one.
        guard kind != .path else {
            #expect(!TypeDeclarations.text.contains("'path'"))
            return
        }

        #expect(
            TypeDeclarations.text.contains("'\(kind.rawValue)'"),
            "the declarations do not offer '\(kind.rawValue)', which the runtime accepts",
        )

        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx",
            source: "params({ a: { type: '\(kind.rawValue)', default: 'x' } })",
            values: [:], duration: 1000, seed: 1,
        ))
        #expect(outcome.declared?.count == 1, "the runtime dropped '\(kind.rawValue)'")
    }

    /// A name the declarations offer but the runtime drops is the worst kind of
    /// wrong, so it is worth naming the one that was actually shipped.
    @Test("a type the runtime rejects is not offered")
    func rejectedTypeIsNotOffered() {
        #expect(EffectParameter.Kind(rawValue: "boolean") == nil)
        #expect(!TypeDeclarations.text.contains("'boolean'"))
    }

    /// `rng` is an object with three methods, not a function.
    ///
    /// Declared as `rng(): number` it type-checked a call that fails at runtime
    /// with "rng is not a function" — and the three methods a script is meant to
    /// use were not declared at all, so the editor could not complete them.
    @Test("rng is declared as the object it is", arguments: ["unit", "between", "integer"])
    func rngIsAnObject(method: String) {
        #expect(TypeDeclarations.text.contains("declare const rng"))
        #expect(!TypeDeclarations.text.contains("declare function rng"))
        #expect(TypeDeclarations.text.contains("\(method)("))

        let call = method == "unit" ? "rng.unit()" : "rng.\(method)(0, 5)"
        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx",
            source: "\(call); sprite('a.png').fade(0, 10, 0, 1)",
            values: [:], duration: 1000, seed: 1,
        ))
        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// The config TypeScript reads carries no key TypeScript rejects.
    ///
    /// A `"//"` comment key is fine at the root and an **error** inside
    /// `compilerOptions`, where every key is validated — and the generated file
    /// shipped two of them, so every project opened with two errors nobody
    /// wrote. That is worse than untidy: declarations that flag code the author
    /// did not write are what teach somebody to switch checking off, and then
    /// the real diagnostics go with it.
    ///
    /// Checked by parsing rather than by reading the string, so a comment moved
    /// back inside fails here rather than in someone's editor.
    @Test("no comment key sits where TypeScript validates keys")
    func configurationHasNoInvalidOptions() throws {
        let data = Data(TypeDeclarations.configuration.utf8)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "the config is not valid JSON",
        )
        let options = try #require(root["compilerOptions"] as? [String: Any])

        for key in options.keys {
            #expect(
                !key.hasPrefix("//"),
                "'\(key)' is a comment inside compilerOptions, which TypeScript rejects",
            )
        }

        // The comments themselves are worth keeping — at the root, where they
        // are ignored rather than validated.
        #expect(root.keys.contains { $0.hasPrefix("//") })
    }

    /// The declaration keys `params` offers are the ones the runtime reads.
    ///
    /// Run through the engine rather than compared against a second list, and
    /// the check is that the declaration **arrives with its options**: the
    /// block offered `choices` while the collector reads `options`, so a script
    /// spelling it the declared way type-checked clean and produced a choice
    /// with nothing to choose from. Silent, like every other drift between
    /// these two halves.
    @Test("a choice's options reach the runtime")
    func choiceOptionsReachRuntime() throws {
        #expect(TypeDeclarations.text.contains("options?: string[]"))
        #expect(!TypeDeclarations.text.contains("choices?:"))

        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx",
            source: "params({ m: { type: 'choice', default: 'a', options: ['a', 'b'] } })",
            values: [:], duration: 1000, seed: 1,
        ))
        let declared = try #require(outcome.declared?.first)
        #expect(declared.options == ["a", "b"], "options did not reach the runtime")
    }
}
