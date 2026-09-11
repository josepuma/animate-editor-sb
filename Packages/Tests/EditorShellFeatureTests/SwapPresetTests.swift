import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Trying a different movement on a clip already placed.
///
/// The case that made it worth building: pick a template, place it, then want
/// a different movement on the *same* clip. There was no way to say that — the
/// clip had to be built again, which is the work presets exist to remove.
@Suite("Swapping a clip's preset", .serialized)
@MainActor
struct SwapPresetTests {
    /// The text survives and the movement changes.
    @Test("swapping keeps the content and takes the movement")
    func swapKeepsContent() throws {
        let shell = EditorShellModel()
        let track = shell.addTrack()
        let node = shell.addEffect(TextEffect.descriptor, at: 0, on: track.id)
        shell.setValue(.text("mi letra"), for: TextEffect.Param.text, on: node.id)

        let drop = try #require(TextEffect.presets.first { $0.id == "drop" })
        shell.applyPreset(drop, to: node.id)

        let after = try #require(shell.effects[node.id])
        #expect(after.values[TextEffect.Param.text] == .text("mi letra"))
        #expect(after.values[TextEffect.Param.stagger] == drop.overrides[TextEffect.Param.stagger])
    }

    /// It is an edit, so it can be taken back.
    ///
    /// Somebody trying presets one after another is exactly who needs undo:
    /// the third one being wrong should not cost the two before it.
    @Test("a swap can be undone")
    func swapIsUndoable() throws {
        let shell = EditorShellModel()
        let track = shell.addTrack()
        let node = shell.addEffect(TextEffect.descriptor, at: 0, on: track.id)
        let before = try #require(shell.effects[node.id]).values

        let scatter = try #require(TextEffect.presets.first { $0.id == "scatter" })
        shell.applyPreset(scatter, to: node.id)
        #expect(shell.effects[node.id]?.values != before, "it changed something")

        shell.undo()

        #expect(shell.effects[node.id]?.values == before)
    }

    /// A locked clip refuses, like every other edit.
    @Test("a locked clip refuses a swap")
    func lockedClipRefuses() throws {
        let shell = EditorShellModel()
        let track = shell.addTrack()
        let node = shell.addEffect(TextEffect.descriptor, at: 0, on: track.id)
        let before = try #require(shell.effects[node.id]).values
        shell.toggleLock(of: track.id)

        let drop = try #require(TextEffect.presets.first { $0.id == "drop" })
        shell.applyPreset(drop, to: node.id)

        #expect(shell.effects[node.id]?.values == before)
    }

    /// An effect that ships no presets offers none, which is what hides the
    /// control rather than showing an empty menu.
    @Test("presets are listed per effect")
    func presetsAreListedPerEffect() {
        let shell = EditorShellModel()

        #expect(!shell.presets(forEffectType: TextEffect.descriptor.type).isEmpty)
        #expect(
            shell.presets(forEffectType: TextEffect.descriptor.type)
                .allSatisfy { $0.effectType == TextEffect.descriptor.type },
            "another effect's presets would mean nothing here",
        )
        #expect(shell.presets(forEffectType: "nothing-ships-this").isEmpty)
    }
}
