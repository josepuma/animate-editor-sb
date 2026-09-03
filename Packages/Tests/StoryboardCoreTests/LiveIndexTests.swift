import Foundation
import Testing

@testable import StoryboardCore

/// A storyboard is mostly *not* on screen at any one moment, so asking every
/// sprite whether it is alive is a scan over work that is almost entirely
/// wasted. Measured on a grid-filtered emitter: 36 sprites drawn out of 14,845,
/// with that scan costing 16ms of a 16.6ms frame while the drawing cost 2.
///
/// The index has to be a pure speed-up: whatever it returns must be exactly
/// what the plain scan returns, or sprites vanish for reasons nobody can see.
@Suite("Live index")
struct LiveIndexTests {
    /// A field where sprites are born at staggered times and live different
    /// lengths — the case a naive cursor gets wrong.
    private func field(count: Int = 500) -> [PreparedSprite] {
        var sprites: [StoryboardSprite] = []
        for i in 0 ..< count {
            let birth = Double(i % 50) * 400
            // Lifetimes from very short to spanning most of the timeline, so a
            // long-lived sprite born early is in the mix.
            let life = Double(50 + (i % 7) * 3000)
            sprites.append(StoryboardSprite(
                id: "s\(i)",
                layer: .foreground,
                origin: .centre,
                filePath: "p.png",
                defaultX: 320,
                defaultY: 240,
                commands: [Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth + life,
                    payload: .fade(start: 0, end: 1),
                )],
                loops: [],
            ))
        }
        return StoryboardResolver.prepare(sprites)
    }

    /// The whole contract: same answer, faster.
    @Test("the index resolves exactly what a full scan does")
    func matchesTheFullScan() {
        let prepared = field()
        let index = StoryboardResolver.LiveIndex(prepared)

        var scanned: [SpriteRenderState] = []
        var scannedIndices: [Int] = []
        var bucketed: [SpriteRenderState] = []
        var bucketedIndices: [Int] = []

        for step in 0 ... 120 {
            let time = Double(step) * 250

            StoryboardResolver.resolve(
                prepared, at: time, into: &scanned, indices: &scannedIndices,
            )
            StoryboardResolver.resolve(
                index, at: time, into: &bucketed, indices: &bucketedIndices,
            )

            #expect(
                scannedIndices == bucketedIndices,
                "at \(time)ms the index found \(bucketedIndices.count) of \(scannedIndices.count)",
            )
        }
    }

    /// Draw order is the only depth cue a storyboard has, so the index must not
    /// reorder anything: a bucket that returned its sprites shuffled would put
    /// background sprites on top.
    @Test("the index preserves draw order")
    func preservesOrder() {
        let prepared = field()
        let index = StoryboardResolver.LiveIndex(prepared)

        var states: [SpriteRenderState] = []
        var indices: [Int] = []

        for step in 0 ... 40 {
            StoryboardResolver.resolve(
                index, at: Double(step) * 500, into: &states, indices: &indices,
            )
            #expect(indices == indices.sorted(), "the bucket returned sprites out of order")
        }
    }

    /// A sprite lives over a *span*, so it belongs to every bucket its life
    /// touches. Filed only by its birth, a long-lived sprite would vanish the
    /// moment the playhead left the bucket it was born in.
    @Test("a long-lived sprite is found long after it was born")
    func longLivedSpritesSurvive() {
        let sprites = [StoryboardSprite(
            id: "long",
            layer: .foreground,
            origin: .centre,
            filePath: "p.png",
            defaultX: 320,
            defaultY: 240,
            commands: [Command(
                easing: .linear,
                startTime: 0,
                endTime: 60_000,
                payload: .fade(start: 0, end: 1),
            )],
            loops: [],
        )]
        let prepared = StoryboardResolver.prepare(sprites)
        let index = StoryboardResolver.LiveIndex(prepared)

        var states: [SpriteRenderState] = []
        var indices: [Int] = []

        // A minute in, well past the bucket it was born in.
        for time in [0.0, 1500, 30_000, 59_000] {
            StoryboardResolver.resolve(index, at: time, into: &states, indices: &indices)
            #expect(states.count == 1, "the sprite disappeared at \(time)ms")
        }
    }

    /// Times outside the storyboard are ordinary — the playhead reaches them.
    @Test("times outside the storyboard resolve to nothing")
    func outOfRangeIsEmpty() {
        let index = StoryboardResolver.LiveIndex(field())

        var states: [SpriteRenderState] = []
        var indices: [Int] = []

        for time in [-50_000.0, 500_000] {
            StoryboardResolver.resolve(index, at: time, into: &states, indices: &indices)
            #expect(states.isEmpty, "found sprites at \(time)ms")
        }
    }

    /// An empty storyboard is a normal state — a project someone just opened.
    @Test("an empty index resolves to nothing")
    func emptyIndex() {
        let index = StoryboardResolver.LiveIndex([])

        var states: [SpriteRenderState] = []
        var indices: [Int] = []
        StoryboardResolver.resolve(index, at: 0, into: &states, indices: &indices)

        #expect(states.isEmpty)
    }
}
