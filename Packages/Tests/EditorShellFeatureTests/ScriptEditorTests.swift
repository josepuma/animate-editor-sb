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

/// Reaching the editor by selecting the clip.
///
/// The editor existed before this and was reachable only by selecting a clip
/// and *then* switching panels by hand — a feature hidden behind knowing it was
/// there.
@Suite("Revealing the script editor")
@MainActor
struct ScriptEditorRevealTests {
    @Test("selecting a script clip opens the script panel")
    func selectingAScriptOpensThePanel() {
        let shell = EditorShellModel()
        shell.sidePanel = .layers
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)

        shell.selectedNodeID = node.id

        #expect(shell.sidePanel == .scripts)
        #expect(shell.isSidePanelVisible)
    }

    /// A hidden panel comes back, since the clip cannot be edited behind it.
    @Test("it opens the panel even when hidden")
    func itOpensAHiddenPanel() {
        let shell = EditorShellModel()
        shell.isSidePanelVisible = false
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)

        shell.selectedNodeID = node.id

        #expect(shell.isSidePanelVisible)
    }

    /// Every other clip leaves the rail alone.
    ///
    /// A panel that changes when it has nothing new to show is a rail moving
    /// for no reason, and it would take the author away from whatever they had
    /// open.
    @Test("selecting any other clip leaves the panel alone")
    func otherClipsLeaveThePanelAlone() {
        let shell = EditorShellModel()
        shell.sidePanel = .assets
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 4000)

        shell.selectedNodeID = node.id

        #expect(shell.sidePanel == .assets)
    }

    /// Deselecting does not take the panel back.
    ///
    /// Switching away is a second decision nobody asked for, and a rail that
    /// moves under you twice per click is worse than one that moves once.
    @Test("deselecting leaves the panel where it is")
    func deselectingKeepsThePanel() {
        let shell = EditorShellModel()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id

        shell.selectedNodeID = nil

        #expect(shell.sidePanel == .scripts)
    }

    /// Selecting the same clip twice is not a second event.
    @Test("reselecting the same clip does not fight a manual panel change")
    func reselectingDoesNotOverride() {
        let shell = EditorShellModel()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id

        // The author goes looking at the assets, with the clip still selected.
        shell.sidePanel = .assets
        shell.selectedNodeID = node.id

        #expect(shell.sidePanel == .assets, "it reopened over a panel the author chose")
    }
}
