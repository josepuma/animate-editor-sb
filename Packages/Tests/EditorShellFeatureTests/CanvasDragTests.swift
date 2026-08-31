import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Canvas drag")
struct CanvasDragTests {
    private func shellWithClip() -> (EditorShellModel, EffectNode.ID) {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)
        shell.selectedNodeID = node?.id
        return (shell, node?.id ?? "")
    }

    /// A gesture is many events, and each one reports its total travel — not
    /// the step since the last. Measuring against the *current* value instead
    /// of the one the gesture began at compounds every step: moving cancelled
    /// itself out and scaling ran away in the wrong direction.
    @Test("a drag is measured from where the gesture began")
    func dragIsRelativeToItsStart() {
        let (shell, id) = shellWithClip()
        let start = shell.effects[id]?.transform[value: .x] ?? 0

        // Three events of one gesture, each reporting cumulative travel.
        shell.applyCanvasDrag(dx: 10, dy: 0, scaleX: 1, scaleY: 1, isFinished: false, at: 0)
        shell.applyCanvasDrag(dx: 20, dy: 0, scaleX: 1, scaleY: 1, isFinished: false, at: 0)

        // Nothing is committed while the hand is down: re-evaluating the clip
        // per event is what made the picture lag behind the pointer.
        #expect(shell.effects[id]?.transform[value: .x] == start)

        shell.applyCanvasDrag(dx: 30, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        // Moved by the final travel, not by their sum.
        #expect(shell.effects[id]?.transform[value: .x] == start + 30)
    }

    @Test("scaling up scales up")
    func scaleDirection() {
        let (shell, id) = shellWithClip()
        let start = shell.effects[id]?.transform[value: .scaleX] ?? 1

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 1.5, scaleY: 1.5, isFinished: true, at: 0)
        #expect((shell.effects[id]?.transform[value: .scaleX] ?? 0) > start)

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 0.5, scaleY: 0.5, isFinished: true, at: 0)
        #expect((shell.effects[id]?.transform[value: .scaleX] ?? 0) < start)
    }

    /// Each gesture starts fresh, or the second drag would build on the first.
    @Test("a new gesture starts from the clip's current place")
    func gesturesAreIndependent() {
        let (shell, id) = shellWithClip()
        let start = shell.effects[id]?.transform[value: .x] ?? 0

        shell.applyCanvasDrag(dx: 10, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)
        shell.applyCanvasDrag(dx: 10, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        #expect(shell.effects[id]?.transform[value: .x] == start + 20)
    }

    /// With the property animated the same drag plants a keyframe instead —
    /// the rule the inspector already follows.
    @Test("dragging an animated property writes a keyframe")
    func animatedPropertiesGetKeyframes() {
        let (shell, id) = shellWithClip()
        shell.beginAnimating(.x, on: id, at: 0)

        shell.applyCanvasDrag(dx: 25, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        #expect((shell.effects[id]?.transform[.x].keyframes.count ?? 0) > 0)
    }

    @Test("a locked clip refuses the drag")
    func lockedClipsRefuse() {
        let (shell, id) = shellWithClip()
        let start = shell.effects[id]?.transform[value: .x] ?? 0
        if let trackID = shell.effects.trackID(of: id) { shell.toggleLock(of: trackID) }

        shell.applyCanvasDrag(dx: 50, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)
        #expect(shell.effects[id]?.transform[value: .x] == start)
    }
}
