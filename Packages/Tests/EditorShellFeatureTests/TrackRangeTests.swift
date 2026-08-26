import StoryboardCore
import Testing

@testable import EditorShellFeature

/// A track showing one bar per sprite would be unreadable at 2,000 sprites and
/// slow to draw, so lifetimes are collapsed into a handful of spans.
@Suite("Track range merging")
struct TrackRangeTests {
    private func sprites(_ ranges: [(Double, Double)]) -> [PreparedSprite] {
        let osb = ranges.enumerated().map { index, range in
            """
            Sprite,Foreground,Centre,"s\(index).png",320,240
            _F,0,\(Int(range.0)),\(Int(range.1)),0,1
            """
        }.joined(separator: "\n")

        return StoryboardResolver.prepare(
            OsbParser.parse("[Events]\n" + osb).sprites,
        )
    }

    @Test("no sprites yields no spans")
    func emptyInput() {
        #expect(TrackRanges.merged(of: []).isEmpty)
    }

    @Test("a single sprite yields its own span")
    func singleSprite() {
        let merged = TrackRanges.merged(of: sprites([(1000, 2000)]))

        #expect(merged.count == 1)
        #expect(merged[0].lowerBound == 1000)
        #expect(merged[0].upperBound == 2000)
    }

    @Test("overlapping sprites merge into one span")
    func mergesOverlapping() {
        let merged = TrackRanges.merged(of: sprites([
            (0, 1000),
            (500, 1500),
            (1200, 2000),
        ]))

        #expect(merged.count == 1)
        #expect(merged[0].lowerBound == 0)
        #expect(merged[0].upperBound == 2000)
    }

    @Test("sprites separated by a wide gap stay apart")
    func keepsDistantSpansApart() {
        let merged = TrackRanges.merged(of: sprites([
            (0, 1000),
            (10000, 11000),
        ]))

        #expect(merged.count == 2)
    }

    @Test("a gap under the threshold is bridged")
    func bridgesSmallGaps() {
        // 200 ms apart reads as continuous at any zoom a whole-track view uses.
        let merged = TrackRanges.merged(of: sprites([
            (0, 1000),
            (1200, 2000),
        ]))

        #expect(merged.count == 1)
        #expect(merged[0].upperBound == 2000)
    }

    @Test("spans come out in order")
    func spansAreSorted() {
        let merged = TrackRanges.merged(of: sprites([
            (20000, 21000),
            (0, 1000),
            (10000, 11000),
        ]))

        #expect(merged.map(\.lowerBound) == merged.map(\.lowerBound).sorted())
    }

    @Test("input order does not change the result")
    func orderIndependent() {
        let ascending = TrackRanges.merged(of: sprites([
            (0, 1000), (5000, 6000), (10000, 11000),
        ]))
        let descending = TrackRanges.merged(of: sprites([
            (10000, 11000), (5000, 6000), (0, 1000),
        ]))

        #expect(ascending.map(\.lowerBound) == descending.map(\.lowerBound))
        #expect(ascending.map(\.upperBound) == descending.map(\.upperBound))
    }

    @Test("a nested sprite does not shorten its containing span")
    func nestedSpriteKeepsOuterBounds() {
        let merged = TrackRanges.merged(of: sprites([
            (0, 10000),
            (2000, 3000),
        ]))

        #expect(merged.count == 1)
        #expect(merged[0].upperBound == 10000)
    }
}
