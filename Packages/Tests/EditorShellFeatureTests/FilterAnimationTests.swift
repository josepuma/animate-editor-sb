import StoryboardCore
import Testing

@testable import EditorShellFeature

/// The moves the inspector's stopwatch makes.
///
/// The view itself cannot be tested, but everything it calls can — and these
/// are the same three moves the transform's stopwatch already has, because a
/// stopwatch has to mean one thing wherever it appears.
@MainActor
@Suite("Filter animation")
struct FilterAnimationTests {
    /// A model holding one clip with a glow on it.
    private func model() -> (EditorShellModel, EffectNode.ID, FilterNode.ID) {
        let shell = EditorShellModel()
        // Through the model's own API, which is what the inspector uses — a
        // test reaching past it would not exercise the same path.
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 2000)
        let filter = shell.addFilter(GlowFilter.descriptor, to: node.id)!
        return (shell, node.id, filter.id)
    }

    private var intensity: String { GlowFilter.Param.intensity }

    /// The first click has to leave something behind, or nothing appears to
    /// have happened — and the key holds what the parameter already had, so
    /// switching animation on changes nothing on screen.
    @Test("the stopwatch plants a key holding the current value")
    func beginAnimatingKeepsTheValue() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterValue(.number(0.4), for: intensity, on: filterID, in: nodeID)

        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 500)

        let track = shell.filterAnimation(intensity, on: filterID, in: nodeID)
        #expect(track?.isActive == true)
        #expect(track?.keyframes.count == 1)
        #expect(track?.keyframes.first?.time == 500)
        #expect(track?.keyframes.first?.value == 0.4)
    }

    /// Switching animation off keeps the keys. Deleting a stopwatch's worth of
    /// work on the click that started it is a trap, and there is no undo here
    /// to climb out of it with.
    @Test("switching animation off keeps the keyframes")
    func disablingKeepsKeys() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(1.5, for: intensity, on: filterID, in: nodeID, at: 1000)

        shell.setFilterAnimationEnabled(
            false, for: intensity, on: filterID, in: nodeID, at: 1000,
        )

        let track = shell.filterAnimation(intensity, on: filterID, in: nodeID)
        #expect(track?.keyframes.count == 2)
        #expect(track?.isEnabled == false)
        #expect(track?.isActive == false)
    }

    /// And it keeps what the animation was worth at that moment: switching it
    /// off is a decision about how a property behaves, not about its value.
    @Test("switching off holds the value it had")
    func disablingHoldsTheValue() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterValue(.number(0.2), for: intensity, on: filterID, in: nodeID)
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(1.8, for: intensity, on: filterID, in: nodeID, at: 1000)

        shell.setFilterAnimationEnabled(
            false, for: intensity, on: filterID, in: nodeID, at: 1000,
        )

        // Not back to the 0.2 it rested at before anyone animated it.
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 1.8)
    }

    /// Planting a key on a switched-off track switches it back on: adding a key
    /// is asking for the thing to animate, and leaving it inert would look like
    /// the click did nothing.
    @Test("adding a key re-enables a disabled track")
    func addingAKeyReenables() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterAnimationEnabled(
            false, for: intensity, on: filterID, in: nodeID, at: 0,
        )

        shell.setFilterKeyframe(1.0, for: intensity, on: filterID, in: nodeID, at: 800)

        #expect(shell.filterAnimation(intensity, on: filterID, in: nodeID)?.isActive == true)
    }

    /// The field shows the value at the playhead while animating, so scrubbing
    /// moves the number — exactly as a transform's does.
    @Test("the value follows the playhead while animating")
    func valueFollowsThePlayhead() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(0.0, for: intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(2.0, for: intensity, on: filterID, in: nodeID, at: 1000)

        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 0)
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 1000) == 2)
        let middle = shell.filterValue(intensity, on: filterID, in: nodeID, at: 500)
        #expect(abs((middle ?? 0) - 1) < 1e-9)
    }

    /// With nothing animating it, the field shows the resting value at every
    /// moment — the playhead must not appear to change a parameter nobody
    /// animated.
    @Test("an unanimated parameter ignores the playhead")
    func restingValueIgnoresThePlayhead() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterValue(.number(0.7), for: intensity, on: filterID, in: nodeID)

        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 0.7)
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 1900) == 0.7)
    }

    /// Deleting is its own action and takes the whole track, keeping what it
    /// was worth so the clip does not jump when the keys go.
    @Test("clearing removes the keys and keeps the value")
    func clearingKeepsTheValue() {
        let (shell, nodeID, filterID) = model()
        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)
        shell.setFilterKeyframe(1.2, for: intensity, on: filterID, in: nodeID, at: 1000)

        shell.clearFilterAnimation(
            for: intensity, on: filterID, in: nodeID, keeping: 1000,
        )

        #expect(shell.filterAnimation(intensity, on: filterID, in: nodeID) == nil)
        #expect(shell.filterValue(intensity, on: filterID, in: nodeID, at: 0) == 1.2)
    }

    /// Keys are clip-local, so one past the end names a moment the clip never
    /// reaches: it would sit in the file, draw in the lane, and never play.
    @Test("a key past the clip's end is clamped into it")
    func keysAreClampedToTheClip() {
        let (shell, nodeID, filterID) = model()
        shell.setFilterKeyframe(1.0, for: intensity, on: filterID, in: nodeID, at: 9000)

        let track = shell.filterAnimation(intensity, on: filterID, in: nodeID)
        #expect(track?.keyframes.first?.time == 2000)
    }

    /// Animating has to reach the canvas. The model's whole job here is to run
    /// the evaluation again, and a stopwatch that changed nothing on screen
    /// would be indistinguishable from a broken one.
    @Test("animating a filter re-evaluates the document")
    func animatingReevaluates() {
        let (shell, nodeID, filterID) = model()
        let before = shell.effectsRevision

        shell.beginAnimatingFilter(intensity, on: filterID, in: nodeID, at: 0)

        #expect(shell.effectsRevision != before)
    }
}
