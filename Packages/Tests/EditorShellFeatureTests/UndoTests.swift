import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Undo, which is the one feature whose failure mode is losing work.
@Suite("Undo")
@MainActor
struct UndoTests {
    private func model() -> EditorShellModel {
        let model = EditorShellModel()
        model.addEffect(EmitterEffect.descriptor, at: 0)
        return model
    }

    /// The check that matters most, and the one the design turns on: a mutating
    /// call through the model has to be recorded. `willSet` fires on in-place
    /// mutation of a value type, but that is exactly the kind of thing worth
    /// proving rather than assuming.
    @Test("an edit can be undone")
    func editIsRecorded() throws {
        let model = model()
        let node = try #require(model.effects.nodes.first)

        model.setValue(.integer(999), for: EmitterEffect.Param.count, on: node.id)
        #expect(model.canUndo)

        model.undo()
        let after = try #require(model.effects[node.id])
        #expect(after.values[EmitterEffect.Param.count] != .integer(999))
    }

    @Test("undo and redo return to where they started")
    func roundTrip() throws {
        let model = model()
        let node = try #require(model.effects.nodes.first)

        model.setValue(.integer(42), for: EmitterEffect.Param.count, on: node.id)
        model.undo()
        model.redo()

        #expect(model.effects[node.id]?.values[EmitterEffect.Param.count] == .integer(42))
    }

    /// Undoing must not itself be recorded, or the stack fills with its own
    /// steps and a second undo goes nowhere.
    @Test("undo does not record itself")
    func undoIsNotAnEdit() throws {
        let model = model()
        let node = try #require(model.effects.nodes.first)

        model.setValue(.integer(1), for: EmitterEffect.Param.count, on: node.id)
        model.setValue(.integer(2), for: EmitterEffect.Param.count, on: node.id)

        model.undo()
        model.undo()

        // Two edits, two undos, back to the start.
        #expect(model.effects[node.id]?.values[EmitterEffect.Param.count] != .integer(1))
        #expect(model.effects[node.id]?.values[EmitterEffect.Param.count] != .integer(2))
    }

    /// A fresh edit throws away the branch that was undone away — the rule
    /// every editor follows, because the alternative is a tree nobody can see.
    @Test("editing after undo clears the redo branch")
    func editClearsRedo() throws {
        let model = model()
        let node = try #require(model.effects.nodes.first)

        model.setValue(.integer(1), for: EmitterEffect.Param.count, on: node.id)
        model.undo()
        #expect(model.canRedo)

        model.setValue(.integer(2), for: EmitterEffect.Param.count, on: node.id)
        #expect(!model.canRedo)
    }

    @Test("nothing to undo at the start")
    func startsEmpty() {
        let model = EditorShellModel()
        #expect(!model.canUndo)
        #expect(!model.canRedo)

        model.undo()
        #expect(model.effects.nodes.isEmpty)
    }

    /// Placing, moving and deleting all go through the same funnel, so all
    /// three come back.
    @Test("a deleted clip comes back")
    func deletionIsUndoable() throws {
        let model = model()
        let node = try #require(model.effects.nodes.first)

        model.removeEffect(node.id)
        #expect(model.effects.nodes.isEmpty)

        model.undo()
        #expect(model.effects.nodes.count == 1)
    }
}
