import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// How the shell treats a script clip.
///
/// What used to be an in-app editor: the code is written in whatever editor
/// the author already uses, so the tests that drove a text field are gone with
/// it. What survives is what still belongs to the shell — which clip declares
/// what, and when the script panel opens.
@Suite("Script clips", .serialized)
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







    /// A declared control reaches the inspector.
    ///
    /// The whole chain: the run declares, the ledger carries it, the shell
    /// adopts it onto the node, and `descriptor(for:)` puts it where the
    /// inspector already looks. Tested end to end because every link was
    /// written separately and each one passing alone has proved not to be the
    /// same thing.
    @Test("a declared control appears in the inspector")
    func declaredControlAppears() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id

        #expect(shell.selectedDescriptor?.parameters.isEmpty == true, "nothing is declared yet")

        // The suite is `.serialized` because these tests await while holding
        // the global seam, and a lock across an `await` is a deadlock waiting
        // — Swift refuses to compile one, correctly. Ordering is the only tool
        // left.
        ScriptRuntime.run = { _ in
            ScriptRuntime.Outcome(
                sprites: [], diagnostics: [], logs: [],
                declared: [EffectParameter(
                    id: "count", name: "Count", group: "Script", defaultValue: .integer(24),
                )],
            )
        }
        defer { ScriptRuntime.run = nil }

        // Through a reload rather than by writing source onto the node: the
        // code lives in a file now, and `reloadScripts()` is the path a save
        // in an external editor actually takes.
        shell.reloadScripts()
        _ = await shell.settledSprites()

        #expect(shell.effects[node.id]?.scriptParameters.count == 1)
        #expect(shell.selectedDescriptor?.parameters.map(\.id) == ["count"])
    }

    /// And a script that declares nothing leaves the inspector alone.
    ///
    /// `param('count') ?? 24` without a `params()` call declares nothing — the
    /// fallback works, but there is no control to show, which is exactly what
    /// it looks like when somebody expects one.
    @Test("reading a param without declaring it shows no control")
    func readingWithoutDeclaringShowsNothing() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id

        ScriptRuntime.run = { _ in
            ScriptRuntime.Outcome(sprites: [], diagnostics: [], logs: [], declared: nil)
        }
        defer { ScriptRuntime.run = nil }

        shell.reloadScripts()
        _ = await shell.settledSprites()

        #expect(shell.selectedDescriptor?.parameters.isEmpty == true)
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

    /// The inspector steps aside on the way in, and stays the author's after.
    ///
    /// It was vetoed outright while a script was open, which meant a script
    /// declaring `params` could not show them — controls that existed and were
    /// unreachable.
    @Test("the inspector closes once, then obeys its button")
    func inspectorStepsAsideOnce() {
        let shell = EditorShellModel()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)

        shell.selectedNodeID = node.id
        #expect(shell.isInspectorVisible == false, "it should step aside on the way in")

        // Opened deliberately, and it stays open.
        shell.isInspectorVisible = true
        shell.selectedNodeID = nil
        shell.selectedNodeID = node.id

        #expect(shell.isInspectorVisible, "it closed a panel the author had opened")
    }

    /// A second script clip does not shut it again either.
    @Test("selecting another script leaves the inspector alone")
    func secondScriptLeavesItAlone() {
        let shell = EditorShellModel()
        let first = shell.addEffect(ScriptEffect.descriptor, at: 0, duration: 4000)
        let second = shell.addEffect(ScriptEffect.descriptor, at: 5000, duration: 4000)

        shell.selectedNodeID = first.id
        shell.isInspectorVisible = true
        shell.selectedNodeID = second.id

        #expect(shell.isInspectorVisible)
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
