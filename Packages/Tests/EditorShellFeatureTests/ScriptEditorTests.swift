import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Editing a script's source from the side panel.
@Suite("Script editor")
@MainActor
struct ScriptEditorTests {
    /// Built through the model's own API, not by assembling a document.
    ///
    /// `effects` has a private setter on purpose — every change has to pass
    /// through the model so `EditHistory` sees it — and a test that reached
    /// around that would be exercising a path the app cannot take.
    private func shellWithScript() -> (EditorShellModel, EffectNode.ID) {
        let shell = EditorShellModel()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id
        return (shell, node.id)
    }

    /// The panel writes through the model, not into the node directly.
    ///
    /// Everything that changes a document goes through the model so undo sees
    /// it: `EditHistory` captures in `effects`' `willSet`, and a write that
    /// side-steps it is a step the author cannot take back.
    @Test("committing source updates the node")
    func commitUpdatesTheNode() {
        let (shell, id) = shellWithScript()

        shell.setScriptSource("sprite(Image.glow)", on: id)

        #expect(shell.effects[id]?.scriptSource == "sprite(Image.glow)")
    }

    /// The whole point of draft-then-commit.
    ///
    /// Writing on every keystroke would recompile and re-evaluate per letter —
    /// and this codebase has already measured what per-keystroke evaluation
    /// does to a slider. A commit is a deliberate act: Return, or leaving the
    /// field.
    @Test("committing the same source changes nothing")
    func committingUnchangedSourceIsANoOp() {
        let (shell, id) = shellWithScript()
        let before = shell.effectsRevision

        shell.setScriptSource(shell.effects[id]?.scriptSource ?? "", on: id)

        #expect(shell.effectsRevision == before, "an unchanged commit re-evaluated the document")
    }

    /// One editing session is one undo entry.
    @Test("an edit can be undone")
    func editCanBeUndone() {
        let (shell, id) = shellWithScript()
        let original = shell.effects[id]?.scriptSource

        shell.setScriptSource("sprite(Image.star)", on: id)
        shell.undo()

        #expect(shell.effects[id]?.scriptSource == original)
    }

    /// A locked track refuses the edit, as it refuses every other change.
    @Test("a locked track refuses a source edit")
    func lockedTrackRefuses() throws {
        let (shell, id) = shellWithScript()
        let original = shell.effects[id]?.scriptSource
        let track = try #require(shell.effects.trackID(of: id))
        shell.toggleLock(of: track)

        shell.setScriptSource("sprite(Image.smoke)", on: id)

        #expect(shell.effects[id]?.scriptSource == original)
    }

    /// The panel only appears for a script clip.
    @Test("the editor is offered only for a script clip")
    func offeredOnlyForScripts() {
        let (shell, _) = shellWithScript()
        #expect(shell.selectedScriptID != nil)

        shell.selectedNodeID = nil
        #expect(shell.selectedScriptID == nil)
    }

    @Test("a non-script clip does not offer the editor")
    func nonScriptDoesNotOffer() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id

        #expect(shell.selectedScriptID == nil)
    }
}
