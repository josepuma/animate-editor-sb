import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Linked scale")
struct LinkedScaleTests {
    private func shellWithClip() -> (EditorShellModel, EffectNode.ID) {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)!
        return (shell, node.id)
    }

    @Test("linked axes move together")
    func linkedAxesFollow() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true

        shell.setScale(2, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 2)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 2)
    }

    /// The lock means one number in both axes. A ratio sounds cleverer and is
    /// not what a lock is asked to do — and computing one from a value already
    /// written sent 0.3 in one axis to 1.5 in the other.
    @Test("linking sets both axes to the same number")
    func linkMatchesBothAxes() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = false
        shell.setScale(2, for: .scaleX, on: id, at: 0)

        shell.scaleIsLinked = true
        shell.setScale(0.3, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 0.3)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 0.3)
    }

    @Test("unlinked axes are independent")
    func unlinkedAxesStayPut() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = false

        shell.setScale(3, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 3)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 1)
    }

    @Test("either axis drives the other")
    func linkWorksBothWays() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true

        shell.setScale(0.5, for: .scaleY, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 0.5)
    }

    @Test("zero is carried across like any other value")
    func zeroRecovers() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true
        shell.setScale(0, for: .scaleX, on: id, at: 0)

        shell.setScale(2, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleY] == 2)
    }

    // ─── The lock on the canvas ──────────────────────────────────────────────

    /// A corner means "make it bigger", so the lock applies: both axes move
    /// together, which is what it already did.
    @Test("a corner drag keeps the axes locked together")
    func cornerObeysTheLock() {
        let (shell, id) = shellWithClip()
        shell.selectedNodeID = id
        shell.scaleIsLinked = true

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 1.5, scaleY: 1.5, isFinished: true, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 1.5)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 1.5)
    }

    /// **The bug this pins.** A side handle exists to stretch one axis, and
    /// with the lock on it scaled the pair — so the frame showed one axis
    /// growing and the clip came out uniform. The preview promised something
    /// the commit did not honour, which is worse than either behaviour on its
    /// own.
    ///
    /// A side ignores the lock, because obeying it makes the handle a second
    /// corner: two controls doing the same thing, one of them for no reason.
    @Test("a side handle stretches one axis even with the lock on")
    func sideIgnoresTheLock() {
        let (shell, id) = shellWithClip()
        shell.selectedNodeID = id
        shell.scaleIsLinked = true

        shell.applyCanvasDrag(
            dx: 0, dy: 0, scaleX: 1, scaleY: 2, isStretch: true, isFinished: true, at: 0,
        )

        #expect(shell.effects[id]?.transform[value: .scaleY] == 2)
        #expect(shell.effects[id]?.transform[value: .scaleX] == 1, "the other axis stays put")
    }

    @Test("a side handle stretches the horizontal axis on its own too")
    func sideStretchesHorizontally() {
        let (shell, id) = shellWithClip()
        shell.selectedNodeID = id
        shell.scaleIsLinked = true

        shell.applyCanvasDrag(
            dx: 0, dy: 0, scaleX: 0.5, scaleY: 1, isStretch: true, isFinished: true, at: 0,
        )

        #expect(shell.effects[id]?.transform[value: .scaleX] == 0.5)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 1)
    }

    /// Which handle it was has to be *passed*, not read off the values. A side
    /// dragged back to exactly 1.0 in its own axis is indistinguishable from a
    /// corner by looking at the numbers, and would be treated as one.
    @Test("a stretch back to no change still stretches")
    func stretchAtUnityIsStillAStretch() {
        let (shell, id) = shellWithClip()
        shell.selectedNodeID = id
        shell.scaleIsLinked = true
        shell.applyCanvasDrag(
            dx: 0, dy: 0, scaleX: 1, scaleY: 3, isStretch: true, isFinished: true, at: 0,
        )

        // Back to 1 on the stretched axis: nothing should reach the other one.
        shell.applyCanvasDrag(
            dx: 0, dy: 0, scaleX: 1, scaleY: 1, isStretch: true, isFinished: true, at: 0,
        )

        #expect(shell.effects[id]?.transform[value: .scaleX] == 1)
    }

    /// With the property animated, the link plants a keyframe on the other axis
    /// too — the same rule every other field follows.
    @Test("linked axes keyframe together when animated")
    func linkedKeyframes() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true
        shell.beginAnimating(.scaleX, on: id, at: 0)
        shell.beginAnimating(.scaleY, on: id, at: 0)

        shell.setScale(3, for: .scaleX, on: id, at: 500)

        #expect((shell.effects[id]?.transform[.scaleY].keyframes.count ?? 0) > 1)
    }
}
