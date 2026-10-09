import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Which clips a click on the canvas may pick.
@MainActor
@Suite("Canvas picking")
struct CanvasPickTests {
    @Test("every clip on an unlocked lane can be picked")
    func unlockedPickable() {
        let shell = EditorShellModel()
        let a = shell.addEffect(ShapeEffect.descriptor, at: 0)
        let lane = shell.addTrack()
        let b = shell.addEffect(ShapeEffect.descriptor, at: 0, on: lane.id)

        #expect(shell.canvasPickableClipIDs == [a.id, b.id])
    }

    /// A locked lane is what lets a full-screen background stay out of the
    /// way: lock it, and clicks reach what is drawn over it.
    @Test("a locked lane is clicked through")
    func lockedIsNot() {
        let shell = EditorShellModel()
        let a = shell.addEffect(ShapeEffect.descriptor, at: 0)
        let lane = shell.addTrack()
        _ = shell.addEffect(ShapeEffect.descriptor, at: 0, on: lane.id)
        shell.toggleLock(of: lane.id)

        #expect(shell.canvasPickableClipIDs == [a.id])
    }

    @Test("picking a clip selects it alone")
    func pickSelects() {
        let shell = EditorShellModel()
        let a = shell.addEffect(ShapeEffect.descriptor, at: 0)
        let b = shell.addEffect(ShapeEffect.descriptor, at: 0)
        shell.selectedNodeID = a.id
        shell.toggleNodeSelection(b.id)

        shell.pickOnCanvas(a.id, adding: false)

        #expect(shell.selectedNodeIDs == [a.id])
    }

    @Test("picking with ⌘ or ⇧ adds to the selection")
    func pickAdds() {
        let shell = EditorShellModel()
        let a = shell.addEffect(ShapeEffect.descriptor, at: 0)
        let b = shell.addEffect(ShapeEffect.descriptor, at: 0)
        shell.selectedNodeID = a.id

        shell.pickOnCanvas(b.id, adding: true)

        #expect(shell.selectedNodeIDs == [a.id, b.id])
    }

    /// Clicking empty canvas clears the selection, as it always has — but an
    /// added click that misses everything is a slip, not a request to drop
    /// the group someone has been building.
    @Test("a plain click on nothing clears; an added one keeps the group")
    func pickNothing() {
        let shell = EditorShellModel()
        let a = shell.addEffect(ShapeEffect.descriptor, at: 0)
        shell.selectedNodeID = a.id

        shell.pickOnCanvas(nil, adding: true)
        #expect(shell.selectedNodeIDs == [a.id])

        shell.pickOnCanvas(nil, adding: false)
        #expect(shell.selectedNodeIDs.isEmpty)
    }
}
