import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// The whole path, from a placed clip to sprites on a timeline.
///
/// Every other suite tests one piece with the others stubbed. This one installs
/// the real runtime and evaluates a real document, because that is the only
/// arrangement that says the pieces fit together — and each of them passing
/// alone has already proved not to be the same thing.
@Suite("Script effect end to end")
struct EndToEndTests {
    private func withRuntime<T>(_ body: () throws -> T) rethrows -> T {
        try ScriptRuntime.withRuntime({ ScriptEngine().run($0) }, body)
    }

    /// The template a fresh clip arrives with has to draw.
    ///
    /// It is the first thing anybody sees, so a template that throws is a
    /// feature that looks broken on first contact — and it exercises most of
    /// the API at once: the loop, `Image`, `Ease`, four command kinds and
    /// `duration`.
    @Test("the starter template draws")
    func starterTemplateDraws() {
        withRuntime {
            var document = EffectDocument()
            let track = document.addTrack(layer: .foreground)
            let node = document.add(ScriptEffect.descriptor, at: 2000, duration: 4000, on: track.id)

            let drawn = EffectEvaluator().evaluate(document)

            #expect(drawn.count == 24, "the template asks for 24 sprites")
            #expect(drawn.allSatisfy { !$0.commands.isEmpty })
            // Shifted into place by the evaluator, not by the script.
            #expect(drawn.allSatisfy { sprite in
                sprite.commands.allSatisfy { $0.timing.startTime >= node.startTime }
            })
            #expect(drawn.allSatisfy { ClipBounds.sprite($0.id, belongsTo: node.id) })
        }
    }

    /// A script's output feeds the existing filters unchanged.
    ///
    /// Nothing in a filter asks which effect produced the sprites it is given,
    /// so this should hold by construction — which is exactly why it is worth
    /// one test rather than an assumption.
    @Test("a filter multiplies a script's output like any other")
    func filtersCompose() {
        withRuntime {
            var document = EffectDocument()
            let track = document.addTrack(layer: .foreground)
            var node = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)

            let bare = EffectEvaluator().evaluate(document).count

            node.filters = [FilterNode(id: "f1", type: "grid", values: [
                "rows": .integer(2),
                "columns": .integer(2),
            ])]
            document[node.id] = node

            let gridded = EffectEvaluator().evaluate(document).count

            #expect(bare > 0)
            #expect(gridded == bare * 4, "a 2×2 grid should quadruple the sprites")
        }
    }

    /// A clip's transform moves what a script drew, as one thing.
    @Test("the clip's transform carries a script's sprites")
    func transformCarries() {
        withRuntime {
            var document = EffectDocument()
            let track = document.addTrack(layer: .foreground)
            var node = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)

            let before = EffectEvaluator().evaluate(document)

            node.transform[value: .x] = 500
            document[node.id] = node

            let after = EffectEvaluator().evaluate(document)

            #expect(before.count == after.count, "moving a clip must move the same sprites, not other ones")
            #expect(before.map(\.id) == after.map(\.id))
            #expect(before.first?.defaultX != after.first?.defaultX)
        }
    }

    /// The clamp holds on the real path, not only in isolation.
    @Test("a runaway script is cut to the ceiling")
    func clampHoldsEndToEnd() {
        withRuntime {
            var node = EffectNode(
                id: "fx", type: ScriptEffect.descriptor.type, name: "Script",
                startTime: 0, duration: 4000, seed: 1,
            )
            node.scriptSource = "for (let i = 0; i < 50000; i++) sprite(Image.soft).fade(0, 10, 0, 1)"

            #expect(EffectEvaluator().evaluate(node).count == ScriptLimits.maximumSprites)
        }
    }

    /// An endless script does not hang the evaluation.
    @Test("an endless script does not hang the document")
    func endlessScriptDoesNotHang() {
        withRuntime {
            var node = EffectNode(
                id: "fx", type: ScriptEffect.descriptor.type, name: "Script",
                startTime: 0, duration: 4000, seed: 1,
            )
            node.scriptSource = "while (true) { sprite(Image.soft) }"

            let started = Date()
            let drawn = EffectEvaluator().evaluate(node)

            // See the note in LoopInstrumentationTests: the claim is that it
            // finishes at all, not that it finishes quickly.
            #expect(Date().timeIntervalSince(started) < 30)
            #expect(drawn.isEmpty)
        }
    }
}
