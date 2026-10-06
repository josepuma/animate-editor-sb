import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Which tab the inspector shows for a clip.
///
/// The tab lives on the model so it outlives the panel's rebuilds — a tab
/// that snapped back to the first one whenever a different clip was picked
/// would make comparing two clips' filters two clicks per glance.
@MainActor
@Suite("Inspector tab")
struct InspectorTabTests {
    @Test("a fresh editor opens on the effect's own parameters")
    func defaultsToEffect() {
        #expect(EditorShellModel().inspectorTab == .effect)
    }

    @Test("picking another clip keeps the tab that was open")
    func survivesSelectionChange() throws {
        let shell = EditorShellModel()
        let first = try #require(shell.addImage(at: "a.png", time: 0))
        let second = try #require(shell.addImage(at: "b.png", time: 1000))

        shell.selectedNodeID = first.id
        shell.inspectorTab = .filters

        shell.selectedNodeID = second.id
        #expect(shell.inspectorTab == .filters)

        // And back again: deselecting is not a reason to forget it either.
        shell.selectedNodeID = nil
        shell.selectedNodeID = first.id
        #expect(shell.inspectorTab == .filters)
    }

    @Test("only a script clip has an output tab")
    func outputIsForScriptsOnly() {
        #expect(InspectorTab.tabs(isScript: true).contains(.output))
        #expect(!InspectorTab.tabs(isScript: false).contains(.output))
    }

    @Test("output on a clip that has none shows effect, and is not forgotten")
    func outputFallsBackWithoutForgetting() {
        let shell = EditorShellModel()
        shell.inspectorTab = .output

        // An emitter has no output: the panel shows Effect…
        #expect(shell.inspectorTab.shown(isScript: false) == .effect)
        // …but the choice stands, so the next script clip opens on Output.
        #expect(shell.inspectorTab == .output)
        #expect(shell.inspectorTab.shown(isScript: true) == .output)
    }
}
