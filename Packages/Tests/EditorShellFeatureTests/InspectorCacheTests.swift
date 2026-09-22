import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Inspector cost cache")
struct InspectorCacheTests {
    /// The inspector reads these from its `body`, which SwiftUI re-runs on
    /// every frame the playhead moves — and each one evaluates the effect in
    /// full. A cache is only safe if an edit is guaranteed to invalidate it.
    @Test("a sprite count follows an edit")
    func countFollowsEdits() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)

        // Awaited, because the count now comes from the last completed pass
        // rather than from evaluating on demand: reading it in the inspector's
        // body used to run the whole effect synchronously, which froze the
        // window for over a second on every value typed.
        shell.setValue(.integer(20), for: EmitterEffect.Param.count, on: node.id)
        await shell.awaitEvaluation()
        let few = shell.spriteCount(of: shell.effects[node.id]!)

        shell.setValue(.integer(200), for: EmitterEffect.Param.count, on: node.id)
        await shell.awaitEvaluation()
        let many = shell.spriteCount(of: shell.effects[node.id]!)

        #expect(many > few)
    }

    @Test("repeated reads of an unchanged node agree")
    func repeatedReadsAgree() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)

        let first = shell.spriteCount(of: node)
        let second = shell.spriteCount(of: node)
        #expect(first == second)
    }
}

/// How far a clip keeps drawing past its own block.
///
/// A particle lives its whole life from wherever it was born, so an emitter
/// releasing right up to the last instant has its final ones on screen seconds
/// later — and the timeline draws that as the faded tail off the end of the
/// block.
///
/// Guarded because moving this calculation off the main thread broke it in a
/// way no test caught: the loops were dropped and the origin was measured from
/// the wrong end. It was visible on screen in seconds and invisible to a suite
/// of 781 tests.
@MainActor
@Suite("Clip tails")
struct ClipTailTests {
    @Test("an emitter's tail reaches past its clip")
    func tailExtendsPastTheClip() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 2000)
        shell.resizeEffect(node.id, startTime: 2000, duration: 3000)
        await shell.awaitEvaluation()

        let tail = shell.tail(of: node.id)
        #expect(tail > 0, "an emitter's particles outlive its clip")
        // Sanity: a tail longer than the clip several times over means the
        // origin was measured from the wrong end.
        #expect(tail < 3000 * 5, "tail of \(tail)ms is not plausible for a 3s clip")
    }

    /// The tail belongs to one pass, before a loop multiplies it.
    @Test("a looped clip reports the same tail as an unlooped one")
    func loopDoesNotChangeTheTail() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        let plain = shell.tail(of: node.id)

        _ = shell.addFilter(LoopFilter.descriptor, to: node.id)
        await shell.awaitEvaluation()
        let looped = shell.tail(of: node.id)

        #expect(abs(plain - looped) < 1, "the tail is a property of one pass")
    }

    /// A clip whose sprites all finish inside it has no tail to draw.
    @Test("a still image has no tail")
    func staticClipHasNoTail() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(ShapeEffect.descriptor, at: 0)
        await shell.awaitEvaluation()

        #expect(shell.tail(of: node.id) == 0)
    }

    /// Editing one clip must not take another clip's tail away.
    ///
    /// A pass now measures only the clip the edit named — every node here costs
    /// a second full evaluation of that node, and doing the whole project on
    /// every edit measured 787ms on a real project against 768ms for the
    /// evaluation itself. The risk that buys is this one: the partial result
    /// holds a single entry, and writing it over the dictionary would zero
    /// every other clip's overhang.
    @Test("editing one clip keeps every other clip's tail")
    func partialPassKeepsOtherTails() async {
        let shell = EditorShellModel()
        let emitter = shell.addEffect(EmitterEffect.descriptor, at: 2000)
        shell.resizeEffect(emitter.id, startTime: 2000, duration: 3000)
        let other = shell.addEffect(ShapeEffect.descriptor, at: 0)
        await shell.awaitEvaluation()

        let before = shell.tail(of: emitter.id)
        #expect(before > 0, "the emitter needs a tail for this to measure anything")

        // An edit naming the *other* clip, so the emitter is not re-measured.
        shell.resizeEffect(other.id, startTime: 0, duration: 4000)
        await shell.awaitEvaluation()

        #expect(shell.tail(of: emitter.id) == before,
                "editing another clip zeroed this one's tail")
    }

    /// A deleted clip's tail must not outlive it.
    ///
    /// Merging rather than assigning is what keeps the other tails, and the
    /// price of a merge is that nothing drops out on its own: an id is reused
    /// when a node is duplicated onto it, so a stale entry would be read as
    /// that new clip's overhang.
    @Test("a deleted clip's tail is dropped")
    func deletedClipDropsItsTail() async {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 2000)
        shell.resizeEffect(node.id, startTime: 2000, duration: 3000)
        await shell.awaitEvaluation()
        #expect(shell.tail(of: node.id) > 0)

        shell.removeEffect(node.id)
        await shell.awaitEvaluation()

        #expect(shell.tail(of: node.id) == 0, "a clip that is gone has no tail")
    }
}
