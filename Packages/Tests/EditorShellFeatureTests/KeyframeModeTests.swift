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

    /// The fallback that reads a lane's only effect is what made the bug
    /// invisible, so it has to keep working where it is meant to.
    @Test("a lane with one effect still resolves without a selection")
    func laneFallbackStillWorks() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        shell.selectedNodeID = nil
        shell.selectedTrackID = shell.effects.trackID(of: node.id)

        #expect(shell.selectedEffect?.id == node.id)
    }

    /// With several effects on a lane there is no "the" effect to show.
    @Test("a lane with several effects resolves to none")
    func crowdedLaneResolvesToNothing() {
        let shell = EditorShellModel()
        let first = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let trackID = shell.effects.trackID(of: first.id)
        _ = shell.addEffect(EmitterEffect.descriptor, at: 5000, duration: 1000, on: trackID)

        shell.selectedNodeID = nil
        shell.selectedTrackID = trackID

        #expect(shell.selectedEffect == nil)
    }
}
