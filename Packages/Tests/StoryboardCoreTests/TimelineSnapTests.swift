import Testing

@testable import StoryboardCore

/// A clip that starts 12 ms after the kick is a clip that starts late, and in
/// a rhythm game that is visible.
@Suite("Timeline snapping")
struct TimelineSnapTests {
    /// 120 BPM in quarters — a line every 125 ms.
    private func grid() -> BeatGrid {
        BeatGrid(
            timing: OsuParser.parse("""
            [TimingPoints]
            0,500,4,2,0,100,1,0
            """),
            divisor: 4,
        )
    }

    // ─── One edge ────────────────────────────────────────────────────────────

    @Test("an edge near a beat lands on it")
    func edgeSnapsToBeat() {
        let snap = TimelineSnap.edge(1010, grid: grid(), anchors: [], threshold: 30)
        #expect(snap.time == 1000)
        #expect(snap.guide == 1000)
    }

    /// Zoomed in, the threshold shrinks below the gap between beats, and the
    /// hand has to be free to place something between them.
    @Test("an edge out of reach of every beat is left alone")
    func edgeOutOfReach() {
        let snap = TimelineSnap.edge(1060, grid: grid(), anchors: [], threshold: 5)
        #expect(snap.time == 1060)
        #expect(snap.guide == nil)
    }

    @Test("the nearest target wins, beat or anchor")
    func nearestWins() {
        // Anchor 3 ms away, beat (2000) 10 ms away.
        let snap = TimelineSnap.edge(1990, grid: grid(), anchors: [1993], threshold: 30)
        #expect(snap.time == 1993)
        #expect(snap.guide == 1993)
    }

    /// A map with no timing points still has other clips and the playhead.
    @Test("without a grid, anchors still catch")
    func anchorsWithoutGrid() {
        let snap = TimelineSnap.edge(4004, grid: nil, anchors: [4000], threshold: 10)
        #expect(snap.time == 4000)
    }

    @Test("an empty grid snaps to nothing")
    func emptyGrid() {
        let empty = BeatGrid(timing: BeatmapTimingData())
        let snap = TimelineSnap.edge(1010, grid: empty, anchors: [], threshold: 30)
        #expect(snap.time == 1010)
        #expect(snap.guide == nil)
    }

    /// The grid is the map's, so it changes with the tempo.
    @Test("the beat follows a tempo change")
    func followsTempo() {
        let grid = BeatGrid(
            timing: OsuParser.parse("""
            [TimingPoints]
            0,500,4,2,0,100,1,0
            10000,250,4,2,0,100,1,0
            """),
            divisor: 4,
        )
        // 62.5 ms per quarter after 10s; at the old tempo the line would be 10000.
        let snap = TimelineSnap.edge(10050, grid: grid, anchors: [], threshold: 30)
        #expect(snap.time == 10063)
    }

    // ─── A whole clip ────────────────────────────────────────────────────────

    /// Both ends are things people line up: a clip starts on the kick, but it
    /// also ends where the next one begins.
    @Test("a moved clip snaps by its end as well as its start")
    func moveSnapsByEnd() {
        let snap = TimelineSnap.move(
            start: 1040, length: 990, grid: nil, anchors: [2025], threshold: 20,
        )
        #expect(snap.time == 1035)
        #expect(snap.guide == 2025)
    }

    @Test("a moved clip snaps by its start")
    func moveSnapsByStart() {
        let snap = TimelineSnap.move(
            start: 1010, length: 333, grid: grid(), anchors: [], threshold: 30,
        )
        #expect(snap.time == 1000)
        #expect(snap.guide == 1000)
    }

    @Test("the edge closer to its target decides")
    func closerEdgeDecides() {
        // Start is 8 from 1000; end (1008 + 500 = 1508) is 2 from 1510.
        let snap = TimelineSnap.move(
            start: 1008, length: 500, grid: nil, anchors: [1000, 1510], threshold: 20,
        )
        #expect(snap.time == 1010)
        #expect(snap.guide == 1510)
    }

    /// ⌘ is the way out: sometimes 1007 is the number someone wants.
    @Test("disabled, nothing moves")
    func disabled() {
        let edge = TimelineSnap.edge(
            1010, grid: grid(), anchors: [], threshold: 30, isEnabled: false,
        )
        #expect(edge.time == 1010)
        #expect(edge.guide == nil)

        let move = TimelineSnap.move(
            start: 1010, length: 100, grid: grid(), anchors: [], threshold: 30, isEnabled: false,
        )
        #expect(move.time == 1010)
        #expect(move.guide == nil)
    }
}
