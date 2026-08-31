import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Delete selection")
struct DeleteSelectionTests {
    private func shellWithKeyframe() -> (EditorShellModel, EffectNode.ID, Keyframe) {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)!
        shell.setKeyframe(1, for: .opacity, at: 0, on: node.id)
        shell.setKeyframe(0, for: .opacity, at: 500, on: node.id)
        let key = shell.effects[node.id]!.transform[.opacity].keyframes[1]
        return (shell, node.id, key)
    }

    /// Pressing Delete while a keyframe is selected destroyed the entire clip,
    /// with no undo to take it back. What is selected is what gets deleted, and
    /// a keyframe is narrower than the clip holding it.
    @Test("deleting a selected keyframe leaves the clip alone")
    func keyframeDeleteKeepsTheClip() {
        let (shell, nodeID, key) = shellWithKeyframe()
        shell.keyframeNodeID = nodeID
        shell.selectedNodeID = nodeID
        shell.selectedKeyframe = EditorShellModel.KeyframeSelection(
            nodeID: nodeID, property: .opacity, keyframeID: key.id,
        )

        shell.deleteSelection()

        #expect(shell.effects[nodeID] != nil)
        #expect(shell.effects[nodeID]?.transform[.opacity].keyframes.count == 1)
    }

    /// Deleting a clip out from under the keys being edited is never what the
    /// key was aimed at.
    @Test("keyframe mode refuses to delete the clip")
    func keyframeModeProtectsTheClip() {
        let (shell, nodeID, _) = shellWithKeyframe()
        shell.keyframeNodeID = nodeID
        shell.selectedNodeID = nodeID
        shell.selectedKeyframe = nil

        shell.deleteSelection()

        #expect(shell.effects[nodeID] != nil)
    }

    /// And outside that mode it still does what it always did.
    @Test("a selected clip is deleted normally")
    func clipDeleteStillWorks() {
        let (shell, nodeID, _) = shellWithKeyframe()
        shell.keyframeNodeID = nil
        shell.selectedNodeID = nodeID

        shell.deleteSelection()

        #expect(shell.effects[nodeID] == nil)
    }
}
