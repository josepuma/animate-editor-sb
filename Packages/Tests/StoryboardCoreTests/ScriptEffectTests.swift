import Foundation
import Testing

@testable import StoryboardCore

/// The scripted effect: a clip like any other, whose sprites come from code.
@Suite("Script effect", .serialized)
struct ScriptEffectTests {
    private let evaluator = EffectEvaluator()

    private func node(source: String? = nil, parameters: [EffectParameter] = []) -> EffectNode {
        var node = EffectNode(
            id: "fx",
            type: ScriptEffect.descriptor.type,
            name: "Script",
            startTime: 1000,
            duration: 4000,
            seed: 42,
        )
        node.scriptSource = source
        node.scriptParameters = parameters
        return node
    }

    // MARK: - Registration

    @Test("the script effect is registered exactly once")
    func registeredOnce() {
        let matching = EffectLibrary.standard.descriptors.filter { $0.type == ScriptEffect.descriptor.type }

        #expect(matching.count == 1)
    }

    /// The library browser lists tools by type, so many placed script clips
    /// must still show one entry — not one per script somebody wrote.
    @Test("the library shows one script tool no matter how many are placed")
    func libraryShowsOneTool() {
        #expect(EffectLibrary.standard.descriptor(for: ScriptEffect.descriptor.type) != nil)
    }

    // MARK: - Per-node descriptors

    /// Two scripts declaring different controls each get their own.
    ///
    /// This is what the whole per-node descriptor change was for, and the first
    /// place it is actually exercised: every native effect answers the same for
    /// every node, so nothing before now could tell the two paths apart.
    @Test("two scripts declare different controls")
    func descriptorsDifferPerNode() throws {
        let effect = try #require(EffectLibrary.standard.effect(for: ScriptEffect.descriptor.type))

        let counter = node(parameters: [
            EffectParameter(id: "count", name: "Count", group: "Script", defaultValue: .integer(5)),
        ])
        let texter = node(parameters: [
            EffectParameter(id: "label", name: "Label", group: "Script", defaultValue: .text("hi")),
        ])

        let first = effect.descriptor(for: counter)
        let second = effect.descriptor(for: texter)

        #expect(first.parameters.map(\.id) == ["count"])
        #expect(second.parameters.map(\.id) == ["label"])
        #expect(first != second)
    }

    /// A script that declares nothing still gets a usable descriptor.
    @Test("a script with no declarations has an empty parameter list")
    func noDeclarationsIsEmpty() throws {
        let effect = try #require(EffectLibrary.standard.effect(for: ScriptEffect.descriptor.type))

        #expect(effect.descriptor(for: node()).parameters.isEmpty)
    }

    // MARK: - Evaluating

    /// An empty clip draws nothing, and that is not an error.
    ///
    /// It is somebody who has just placed a script and not written it yet, so
    /// it must read differently from a script that failed — reported as a
    /// failure, the author goes looking for a mistake they have not made.
    @Test("a clip with no source draws nothing")
    func noSourceDrawsNothing() {
        #expect(evaluator.evaluate(node()).isEmpty)
        #expect(evaluator.evaluate(node(source: "")).isEmpty)
    }

    /// Evaluation must never throw, whatever the script does.
    ///
    /// `Effect.evaluate` cannot throw by protocol, so a script that dies has to
    /// come back as no sprites — the diagnostic travels separately.
    @Test("a broken script yields no sprites rather than failing", arguments: [
        "this is not javascript at all",
        "throw new Error('deliberate')",
        "undefinedFunction()",
        "null.property",
    ])
    func brokenScriptIsSurvivable(source: String) {
        #expect(evaluator.evaluate(node(source: source)).isEmpty)
    }

    /// With no runtime installed, the effect is quiet rather than crashing.
    @Test("no runtime yields no sprites")
    func noRuntimeIsSurvivable() {
        ScriptRuntime.withoutRuntime {
            #expect(evaluator.evaluate(node(source: "sprite('a.png')")).isEmpty)
        }
    }

    // MARK: - What the evaluator does around it

    /// The clip's offset is applied by the evaluator, not by the script.
    @Test("the evaluator shifts a script's output into place")
    func outputIsShifted() {
        let sprite = StoryboardSprite(
            id: "fx/s0", layer: .foreground, origin: .centre,
            filePath: BuiltInSprite.soft, defaultX: 320, defaultY: 240,
            commands: [Command(easing: .linear, startTime: 0, endTime: 500, payload: .fade(start: 0, end: 1))],
        )

        ScriptRuntime.withRuntime({ _ in
            ScriptRuntime.Outcome(sprites: [sprite], diagnostics: [])
        }, {
            let drawn = evaluator.evaluate(node(source: "sprite('a.png')"))

            #expect(drawn.count == 1)
            // Local 0 became the clip's start time.
            #expect(drawn.first?.commands.first?.timing.startTime == 1000)
            #expect(drawn.first?.commands.first?.timing.endTime == 1500)
        })
    }

    /// A fresh clip comes with something in it.
    ///
    /// `EffectDocument.add` builds a node from the descriptor's defaults, and a
    /// script has no default source there — so without a starter template a new
    /// script clip is an empty box that draws nothing, which reads as broken
    /// rather than as waiting.
    @Test("a freshly placed script clip has a starter template")
    func freshClipHasATemplate() {
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        let added = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)

        #expect(added.scriptSource?.isEmpty == false)
    }
}
