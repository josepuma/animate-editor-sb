import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Placing a clip is one undo step, however many writes it takes.
///
/// **The bug this pins**: every placement fills its node in after
/// `effects.add` — a preset's name, values and layers, an image's path, a
/// paste's everything — and each write to `effects` recorded its own undo
/// snapshot. Placing a preset took two ⌘Z: the first left the clip at its
/// defaults, a state the author was never in, and only the second removed it.
@MainActor
@Suite("Placement undo")
struct PlacementUndoTests {
    @Test("a preset is undone in one step")
    func preset() throws {
        let shell = EditorShellModel()
        let preset = try #require(shell.presets.first)

        shell.addPreset(preset, at: 0)
        #expect(shell.effects.nodes.count == 1)

        shell.undo()
        #expect(shell.effects.nodes.isEmpty)
    }

    @Test("an image is undone in one step")
    func image() {
        let shell = EditorShellModel()

        shell.addImage(at: "sb/bg.png", time: 0)
        shell.undo()

        #expect(shell.effects.nodes.isEmpty)
    }

    @Test("a paste is undone in one step, leaving the original")
    func paste() throws {
        let shell = EditorShellModel()
        let preset = try #require(shell.presets.first)
        shell.addPreset(preset, at: 0)
        shell.copySelectedEffect()

        shell.pasteEffect(at: 5000)
        #expect(shell.effects.nodes.count == 2)

        shell.undo()
        #expect(shell.effects.nodes.count == 1)
    }

    @Test("redo brings a placement back whole, not at its defaults")
    func redoRestoresTheWholeClip() throws {
        let shell = EditorShellModel()
        let preset = try #require(shell.presets.first)
        let placed = try #require(shell.addPreset(preset, at: 0))

        shell.undo()
        shell.redo()

        #expect(shell.effects[placed.id]?.name == preset.name)
        #expect(shell.effects[placed.id]?.values == placed.values)
    }
}
