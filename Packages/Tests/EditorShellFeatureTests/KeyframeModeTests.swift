import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Keyframe mode")
struct KeyframeModeTests {
    /// Opening a clip's keyframes is working on that clip, so it has to be the
    /// selected one.
    ///
    /// Without this, double-clicking in a freshly opened project left nothing
    /// selected: the inspector fell back to the lane and drew a track's heading
    /// over the effect's own parameters. It only looked right when a plain
    /// click had happened first.
    @Test("opening keyframes selects the clip")
    func openingSelectsTheClip() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        shell.selectedNodeID = nil

        shell.keyframeNodeID = node.id
        shell.selectedNodeID = node.id

        #expect(shell.selectedEffect?.id == node.id)
        #expect(shell.keyframeNodeID == node.id)
    }

    /// Nothing selected means an empty panel, whatever lane is still lit.
    @Test("deselecting a clip empties the panel")
    func deselectingEmptiesThePanel() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        shell.selectedTrackID = shell.effects.trackID(of: node.id)

        shell.selectedNodeID = nil

        #expect(shell.selectedEffect == nil)
    }
}
