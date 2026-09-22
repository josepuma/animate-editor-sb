import Foundation
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Arrow keys move the playhead along the map's own grid.
@Suite("Playhead nudging")
@MainActor
struct PlayheadNudgeTests {
    /// 120 BPM — one beat every 500 ms, four to a measure.
    private func steadyGrid() -> BeatGrid {
        BeatGrid(
            timing: OsuParser.parse("""
            [TimingPoints]
            0,500,4,2,0,100,1,0
            """),
            divisor: 1,
        )
    }

    /// A model with a clip long enough to nudge inside, and a seek seam that
    /// records where it was sent.
    private func model(withBeat: Bool = true) -> (EditorShellModel, Box) {
        let shell = EditorShellModel()
        _ = shell.addEffect(ShapeEffect.descriptor, at: 0)
        if withBeat { shell.beat = steadyGrid() }

        let box = Box()
        shell.seekHandler = { box.value = $0 }
        return (shell, box)
    }

    final class Box: @unchecked Sendable {
        var value: Double?
    }

    @Test("an arrow moves one beat forward")
    func stepsForwardByABeat() {
        let (shell, box) = model()
        shell.playheadTime = 1200
        shell.nudgePlayhead(by: .beat, forward: true)
        // 120 BPM: beats at 1000, 1500, 2000…
        #expect(box.value == 1500)
    }

    @Test("an arrow moves one beat back")
    func stepsBackByABeat() {
        let (shell, box) = model()
        shell.playheadTime = 1200
        shell.nudgePlayhead(by: .beat, forward: false)
        #expect(box.value == 1000)
    }

    /// The whole point of stepping by beat rather than by milliseconds: the
    /// playhead lands where things get placed.
    @Test("a beat step lands on a beat, not near one")
    func landsOnTheGrid() {
        let (shell, box) = model()
        shell.playheadTime = 1237
        shell.nudgePlayhead(by: .beat, forward: true)
        let landed = try! #require(box.value)
        #expect(landed.truncatingRemainder(dividingBy: 500) == 0,
                "expected a beat, got \(landed)")
    }

    @Test("shift steps a whole bar")
    func stepsByABar() {
        let (shell, box) = model()
        shell.playheadTime = 1200
        shell.nudgePlayhead(by: .bar, forward: true)
        // Four beats to a measure at 500 ms each: downbeats at 0, 2000, 4000…
        #expect(box.value == 2000)
    }

    @Test("a bar step is four times a beat step")
    func barIsBiggerThanBeat() {
        let (shell, beatBox) = model()
        shell.playheadTime = 0
        shell.nudgePlayhead(by: .beat, forward: true)
        let beat = try! #require(beatBox.value)

        let (other, barBox) = model()
        other.playheadTime = 0
        other.nudgePlayhead(by: .bar, forward: true)
        let bar = try! #require(barBox.value)

        #expect(bar > beat, "a bar (\(bar)) has to outrun a beat (\(beat))")
    }

    /// A map missing its timing points still has to respond: arrow keys doing
    /// nothing would read as the editor being broken.
    @Test("a map with no timing still moves")
    func fallsBackWithoutABeat() {
        let (shell, box) = model(withBeat: false)
        shell.playheadTime = 1000
        shell.nudgePlayhead(by: .beat, forward: true)
        let landed = try! #require(box.value)
        #expect(landed > 1000, "expected to move, stayed at \(landed)")
    }

    /// The playhead cannot be nudged out of the piece.
    @Test("a nudge stays inside the piece")
    func clampsToTheRange() {
        let (shell, box) = model()
        let range = try! #require(shell.playedTimeRange)
        // Parked at the very start and stepping back, so an unclamped nudge
        // has somewhere wrong to go.
        shell.playheadTime = range.lowerBound
        shell.nudgePlayhead(by: .bar, forward: false)
        let landed = try! #require(box.value)
        #expect(landed >= range.lowerBound,
                "went to \(landed), below \(range.lowerBound)")

        // And past the end, the other edge of the same guard.
        shell.playheadTime = range.upperBound
        shell.nudgePlayhead(by: .bar, forward: true)
        let past = try! #require(box.value)
        #expect(past <= range.upperBound,
                "went to \(past), past \(range.upperBound)")
    }
}
