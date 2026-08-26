import Testing

@testable import StoryboardCore

@Suite("BeatGrid")
struct BeatGridTests {
    /// 120 BPM — one beat every 500 ms, four to a measure.
    private func steadyGrid(divisor: Int = 4) -> BeatGrid {
        BeatGrid(
            timing: OsuParser.parse("""
            [TimingPoints]
            0,500,4,2,0,100,1,0
            """),
            divisor: divisor,
        )
    }

    /// 120 BPM until 10s, then 240 BPM.
    private func tempoChangeGrid(divisor: Int = 1) -> BeatGrid {
        BeatGrid(
            timing: OsuParser.parse("""
            [TimingPoints]
            0,500,4,2,0,100,1,0
            10000,250,4,2,0,100,1,0
            """),
            divisor: divisor,
        )
    }

    // ─── Basics ──────────────────────────────────────────────────────────────

    @Test("a grid with no timing points is empty")
    func emptyGrid() {
        let grid = BeatGrid(timing: BeatmapTimingData())

        #expect(grid.isEmpty)
        #expect(grid.primaryBPM == nil)
        #expect(grid.lines(in: 0...10_000).isEmpty)
    }

    @Test("reports the map's nominal tempo")
    func reportsPrimaryBPM() {
        #expect(steadyGrid().primaryBPM == 120)
    }

    @Test("tempo follows the governing timing point")
    func tempoFollowsTimingPoint() {
        let grid = tempoChangeGrid()

        #expect(grid.bpm(at: 5000) == 120)
        #expect(grid.bpm(at: 15000) == 240)
    }

    @Test("the divisor is clamped to at least one")
    func divisorIsClamped() {
        #expect(BeatGrid(timing: BeatmapTimingData(), divisor: 0).divisor == 1)
        #expect(BeatGrid(timing: BeatmapTimingData(), divisor: -4).divisor == 1)
    }

    // ─── Snapping ────────────────────────────────────────────────────────────

    @Test("snaps to the nearest subdivision")
    func snapsToNearest() {
        // 1/4 of a 500 ms beat is 125 ms, so the midpoint is 62.5 ms.
        let grid = steadyGrid()

        #expect(grid.snap(0) == 0)
        #expect(grid.snap(60) == 0, "just below the midpoint rounds down")
        #expect(grid.snap(70) == 125, "just above the midpoint rounds up")
        #expect(grid.snap(130) == 125)
        #expect(grid.snap(500) == 500)
    }

    @Test("snapping respects the divisor")
    func snapRespectsDivisor() {
        #expect(steadyGrid(divisor: 1).snap(200) == 0)
        #expect(steadyGrid(divisor: 1).snap(300) == 500)
        #expect(steadyGrid(divisor: 2).snap(200) == 250)
    }

    // ─── Navigation ──────────────────────────────────────────────────────────

    @Test("steps forward one subdivision")
    func stepsForward() {
        let grid = steadyGrid(divisor: 1)

        #expect(grid.nextBeat(after: 0) == 500)
        #expect(grid.nextBeat(after: 200) == 500)
        #expect(grid.nextBeat(after: 500) == 1000)
    }

    @Test("steps backward one subdivision")
    func stepsBackward() {
        let grid = steadyGrid(divisor: 1)

        #expect(grid.previousBeat(before: 1000) == 500)
        #expect(grid.previousBeat(before: 800) == 500)
        #expect(grid.previousBeat(before: 500) == 0)
    }

    @Test("stepping forward stops on a tempo change")
    func forwardStopsAtTempoChange() {
        // The last beat of the 120 BPM section falls at 9500; the next step
        // must land on the new timing point rather than overshooting to 10000
        // by the old tempo.
        let grid = tempoChangeGrid()
        #expect(grid.nextBeat(after: 9600) == 10000)
    }

    @Test("stepping backward crosses into the previous tempo")
    func backwardCrossesTempoChange() {
        let grid = tempoChangeGrid()
        let previous = grid.previousBeat(before: 10000)

        #expect(previous < 10000)
        #expect(previous >= 9000, "should land on a beat of the slower section")
    }

    @Test("navigation is a no-op without timing points")
    func navigationWithoutTiming() {
        let grid = BeatGrid(timing: BeatmapTimingData())

        #expect(grid.snap(1234) == 1234)
        #expect(grid.nextBeat(after: 1234) == 1234)
        #expect(grid.previousBeat(before: 1234) == 1234)
    }

    // ─── Grid generation ─────────────────────────────────────────────────────

    @Test("generates one line per beat")
    func generatesLinesPerBeat() {
        let lines = steadyGrid(divisor: 1).lines(in: 0...2000)

        #expect(lines.map(\.time) == [0, 500, 1000, 1500, 2000])
    }

    @Test("marks downbeats as major")
    func marksDownbeats() {
        // Four beats to a measure at 1/1, so every fourth line is a downbeat.
        let lines = steadyGrid(divisor: 1).lines(in: 0...4000)
        let majors = lines.filter(\.isMajor).map(\.time)

        #expect(majors == [0, 2000, 4000])
    }

    @Test("subdivisions increase the line count")
    func subdivisionsAddLines() {
        let whole = steadyGrid(divisor: 1).lines(in: 0...1000).count
        let quarters = steadyGrid(divisor: 4).lines(in: 0...1000).count

        #expect(quarters > whole)
        #expect(quarters == 9, "0 to 1000 ms at 125 ms intervals")
    }

    @Test("only the requested range is generated")
    func generatesOnlyRequestedRange() {
        let lines = steadyGrid(divisor: 1).lines(in: 5000...6000)

        #expect(lines.allSatisfy { $0.time >= 5000 && $0.time <= 6000 })
        #expect(!lines.isEmpty)
    }

    @Test("lines come out in order")
    func linesAreSorted() {
        let lines = tempoChangeGrid(divisor: 4).lines(in: 0...20_000)
        #expect(lines.map(\.time) == lines.map(\.time).sorted())
    }

    @Test("line spacing tightens after a tempo change")
    func spacingFollowsTempo() {
        let grid = tempoChangeGrid()

        let slow = grid.lines(in: 0...2000).map(\.time)
        let fast = grid.lines(in: 10_000...12_000).map(\.time)

        // 120 BPM gives 500 ms beats; 240 BPM gives 250 ms.
        #expect(slow[1] - slow[0] == 500)
        #expect(fast[1] - fast[0] == 250)
    }

    @Test("an empty range yields nothing")
    func emptyRange() {
        #expect(steadyGrid().lines(in: 1000...1000).count <= 1)
    }

    @Test("a range before the first timing point still produces lines")
    func rangeBeforeFirstPoint() {
        let grid = BeatGrid(
            timing: OsuParser.parse("""
            [TimingPoints]
            5000,500,4,2,0,100,1,0
            """),
            divisor: 1,
        )

        // Nothing precedes the first point, so the grid starts there.
        let lines = grid.lines(in: 0...6000)
        #expect(lines.allSatisfy { $0.time >= 5000 })
    }
}
