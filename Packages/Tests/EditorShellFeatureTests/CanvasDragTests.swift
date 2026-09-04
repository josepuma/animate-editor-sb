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

    /// **The bug this pins.** The baseline a drag measures from was cached
    /// without recording which clip it belonged to, and only cleared on a
    /// finished event. Select another clip — a duplicate, say — and its first
    /// drag measured from the previous clip's position.
    ///
    /// Logged on a shape duplicated to x 720: the baseline came back as −108,
    /// where the original had been left, so the copy jumped somewhere neither
    /// the hand nor the inspector had asked for.
    @Test("a drag measures from the clip being dragged")
    func baselineBelongsToItsClip() throws {
        let shell = EditorShellModel()
        let first = try #require(shell.addImage(at: "a.png", time: 0))
        let second = try #require(shell.addImage(at: "b.png", time: 0))

        shell.setTransformValue(100, for: .x, on: first.id)
        shell.setTransformValue(700, for: .x, on: second.id)

        // A gesture on the first clip, left unfinished — which is all it takes.
        shell.selectedNodeID = first.id
        shell.applyCanvasDrag(dx: 30, dy: 0, scaleX: 1, scaleY: 1, isFinished: false, at: 0)

        // Now the second one.
        shell.selectedNodeID = second.id
        shell.applyCanvasDrag(dx: 50, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        #expect(
            shell.effects[second.id]?.transform[value: .x] == 750,
            "the copy moved from the other clip's position",
        )
        #expect(shell.effects[first.id]?.transform[value: .x] == 100, "the first one never committed")
    }

    /// Within one clip the baseline still holds for the whole gesture, which is
    /// what stops each event compounding on the last.
    @Test("the baseline survives a gesture on one clip")
    func baselineHoldsWithinAGesture() throws {
        let shell = EditorShellModel()
        let node = try #require(shell.addImage(at: "a.png", time: 0))
        shell.selectedNodeID = node.id
        shell.setTransformValue(100, for: .x, on: node.id)

        shell.applyCanvasDrag(dx: 10, dy: 0, scaleX: 1, scaleY: 1, isFinished: false, at: 0)
        shell.applyCanvasDrag(dx: 20, dy: 0, scaleX: 1, scaleY: 1, isFinished: false, at: 0)
        shell.applyCanvasDrag(dx: 30, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        #expect(shell.effects[node.id]?.transform[value: .x] == 130)
    }

    // ─── The lock ────────────────────────────────────────────────────────────

    /// **The bug this pins is the silence, not the refusal.**
    ///
    /// A locked clip correctly refuses to move, and the canvas said nothing
    /// about it: the frame's locked styling was implemented but fed a literal
    /// `false`, and the box opted out of hit testing entirely, so a drag
    /// reached the canvas underneath and simply did nothing. Measured on a real
    /// session: 65 drag events rejected in a row with no feedback of any kind,
    /// which reads as a broken control rather than a locked one.
    @Test("a locked selection reports itself as locked")
    func lockedSelectionSaysSo() throws {
        let shell = EditorShellModel()
        let node = try #require(shell.addImage(at: "a.png", time: 0))
        shell.selectedNodeID = node.id

        #expect(shell.isSelectionLocked == false)

        let trackID = try #require(shell.effects.trackID(of: node.id))
        shell.toggleLock(of: trackID)

        #expect(shell.isSelectionLocked, "the canvas has no way to know it is locked")
    }

    @Test("nothing selected is not locked")
    func noSelectionIsNotLocked() {
        #expect(EditorShellModel().isSelectionLocked == false)
    }

    /// The refusal itself, which was never the broken half.
    @Test("a locked clip does not move")
    func lockedClipStaysPut() throws {
        let shell = EditorShellModel()
        let node = try #require(shell.addImage(at: "a.png", time: 0))
        shell.selectedNodeID = node.id
        shell.setTransformValue(100, for: .x, on: node.id)

        let trackID = try #require(shell.effects.trackID(of: node.id))
        shell.toggleLock(of: trackID)

        shell.applyCanvasDrag(dx: 50, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        #expect(shell.effects[node.id]?.transform[value: .x] == 100)
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
