import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Paste")
struct PasteTests {
    private func shellWithCopy() -> EditorShellModel {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 1000)!
        shell.selectedNodeID = node.id
        shell.copySelectedEffect()
        return shell
    }

    /// A paste lands where you are looking, which is the playhead — not back at
    /// the start of the track, and not where the original happened to sit.
    @Test("a paste lands at the playhead")
    func pasteLandsAtThePlayhead() {
        let shell = shellWithCopy()
        shell.playheadTime = 7500

        let pasted = shell.pasteEffect(at: shell.playheadTime)

        #expect(pasted?.startTime == 7500)
    }

    /// The shortcut reads the playhead from the model rather than from its own
    /// view: the buttons live in a `.background` SwiftUI has no reason to
    /// rebuild as the clock moves, so a captured time stayed at whatever the
    /// editor opened with and every paste landed at zero.
    @Test("the model's playhead follows the clock")
    func modelTracksTheClock() {
        let shell = shellWithCopy()

        shell.playheadTime = 4200
        #expect(shell.pasteEffect(at: shell.playheadTime)?.startTime == 4200)

        shell.playheadTime = 9100
        #expect(shell.pasteEffect(at: shell.playheadTime)?.startTime == 9100)
    }

    @Test("a paste keeps the original's settings but not its identity")
    func pasteCarriesSettings() {
        let shell = shellWithCopy()
        let source = shell.copiedNode!
        shell.playheadTime = 2000

        let pasted = shell.pasteEffect(at: shell.playheadTime)

        #expect(pasted?.id != source.id)
        #expect(pasted?.values == source.values)
        #expect(pasted?.duration == source.duration)
    }

    /// A clip is what it does *and* how it looks. A copy that quietly drops
    /// the glow someone tuned is a copy of the wrong thing.
    @Test("a paste carries the clip's filters")
    func pasteCarriesFilters() {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)!
        shell.addFilter(GlowFilter.descriptor, to: node.id)
        shell.selectedNodeID = node.id
        shell.copySelectedEffect()

        let pasted = shell.pasteEffect(at: 3000)

        #expect(pasted?.filters.count == 1)
        #expect(pasted?.filters.first?.type == GlowFilter.descriptor.type)
    }

    /// The id prefixes the sprites a filter derives, so two nodes sharing it
    /// would name the same ones — and a wiggle seeded from it would wobble
    /// identically in both.
    @Test("copied filters get their own identity")
    func copiedFiltersAreReidentified() {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)!
        shell.addFilter(GlowFilter.descriptor, to: node.id)
        shell.selectedNodeID = node.id
        shell.copySelectedEffect()

        let original = shell.effects[node.id]!.filters.first!
        let pasted = shell.pasteEffect(at: 3000)!.filters.first!

        #expect(pasted.id != original.id)
    }

    @Test("a duplicate carries its filters too")
    func duplicateCarriesFilters() {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)!
        shell.addFilter(GlowFilter.descriptor, to: node.id)

        let copy = shell.duplicateEffect(node.id)

        #expect(copy?.filters.count == 1)
        #expect(copy?.filters.first?.id != shell.effects[node.id]?.filters.first?.id)
    }

    @Test("a paste before zero is held at the start")
    func pasteClampsAtZero() {
        let shell = shellWithCopy()
        #expect(shell.pasteEffect(at: -500)?.startTime == 0)
    }
}
