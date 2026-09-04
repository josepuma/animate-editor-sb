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

/// The same rule, one kind of keyframe later.
///
/// A filter's key was invisible to `deleteSelection` exactly as a transform's
/// once was — every selection the method can see has to be listed, or Delete
/// quietly reaches past it for something bigger.
@MainActor
@Suite("Delete selection · filter keyframes")
struct FilterDeleteSelectionTests {
    private func model() -> (EditorShellModel, EffectNode.ID, FilterNode.ID, Keyframe.ID) {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 2000)
        let filter = shell.addFilter(GlowFilter.descriptor, to: node.id)!
        shell.beginAnimatingFilter(
            GlowFilter.Param.intensity, on: filter.id, in: node.id, at: 500,
        )
        let key = shell.filterAnimation(
            GlowFilter.Param.intensity, on: filter.id, in: node.id,
        )!.keyframes.first!
        return (shell, node.id, filter.id, key.id)
    }

    @Test("Delete removes a selected filter keyframe")
    func deleteRemovesFilterKey() {
        let (shell, nodeID, filterID, keyID) = model()
        shell.selectedFilterKeyframe = EditorShellModel.FilterKeyframeSelection(
            nodeID: nodeID, filterID: filterID,
            parameter: GlowFilter.Param.intensity, keyframeID: keyID,
        )

        shell.deleteSelection()

        #expect(shell.filterAnimation(
            GlowFilter.Param.intensity, on: filterID, in: nodeID,
        ) == nil)
    }

    /// **The one that matters.** Delete must take the key and nothing else —
    /// the clip and its filter have to survive. This is the shape of the bug
    /// that once destroyed a whole clip.
    @Test("Delete on a filter key spares the clip and the filter")
    func deleteSparesTheClip() {
        let (shell, nodeID, filterID, keyID) = model()
        shell.selectedFilterKeyframe = EditorShellModel.FilterKeyframeSelection(
            nodeID: nodeID, filterID: filterID,
            parameter: GlowFilter.Param.intensity, keyframeID: keyID,
        )

        shell.deleteSelection()

        #expect(shell.effects[nodeID] != nil, "the clip must survive")
        #expect(
            shell.effects[nodeID]?.filters.contains { $0.id == filterID } == true,
            "the filter must survive",
        )
    }

    /// With a key selected, Delete does not reach past it for the clip even
    /// though the clip is selected too — it is selected only because its keys
    /// are being edited.
    @Test("a selected key wins over the clip that holds it")
    func keyWinsOverClip() {
        let (shell, nodeID, filterID, keyID) = model()
        shell.selectedNodeID = nodeID
        shell.selectedFilterKeyframe = EditorShellModel.FilterKeyframeSelection(
            nodeID: nodeID, filterID: filterID,
            parameter: GlowFilter.Param.intensity, keyframeID: keyID,
        )

        shell.deleteSelection()

        #expect(shell.effects[nodeID] != nil)
    }
}
