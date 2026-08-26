import Testing

@testable import EditorShellFeature

/// Marks brighten over a short ramp rather than switching the instant the
/// playhead crosses them, which would make the row flicker.
@Suite("Waveform played ratio")
struct PlayedRatioTests {
    private func ratio(atX x: Double, currentTime: Double) -> Double {
        TrackTimelineView.playedRatio(
            atX: x,
            width: 1000,
            currentTime: currentTime,
            duration: 1000,
        )
    }

    @Test("marks well behind the playhead are fully played")
    func behindPlayheadIsFull() {
        // The playhead sits at x = 500 for this duration and width.
        #expect(ratio(atX: 100, currentTime: 500) == 1)
        #expect(ratio(atX: 400, currentTime: 500) == 1)
    }

    @Test("marks ahead of the playhead are unplayed")
    func aheadOfPlayheadIsZero() {
        #expect(ratio(atX: 500, currentTime: 500) == 0)
        #expect(ratio(atX: 900, currentTime: 500) == 0)
    }

    @Test("marks inside the ramp are partly played")
    func rampIsGradual() {
        let justBehind = ratio(atX: 495, currentTime: 500)
        let further = ratio(atX: 485, currentTime: 500)

        #expect(justBehind > 0 && justBehind < 1)
        #expect(further > justBehind, "brightness grows with distance behind")
    }

    @Test("the ratio stays within bounds everywhere")
    func staysInBounds() {
        for x in stride(from: 0.0, through: 1000, by: 25) {
            let value = ratio(atX: x, currentTime: 500)
            #expect(value >= 0 && value <= 1, "out of range at x=\(x)")
        }
    }

    @Test("nothing beyond the start is played at time zero")
    func nothingPlayedAtStart() {
        // The ruler is inset, so the playhead sits a few points in at time
        // zero and marks within the ramp of it read as partly played. What
        // matters is that nothing further along does.
        #expect(ratio(atX: 100, currentTime: 0) == 0)
        #expect(ratio(atX: 500, currentTime: 0) == 0)
    }

    @Test("everything is played at the end")
    func everythingPlayedAtEnd() {
        #expect(ratio(atX: 0, currentTime: 1000) == 1)
        #expect(ratio(atX: 900, currentTime: 1000) == 1)
    }

    @Test("a zero duration or width reports nothing played")
    func degenerateInputs() {
        #expect(
            TrackTimelineView.playedRatio(
                atX: 100, width: 1000, currentTime: 500, duration: 0,
            ) == 0,
        )
        #expect(
            TrackTimelineView.playedRatio(
                atX: 100, width: 0, currentTime: 500, duration: 1000,
            ) == 0,
        )
    }
}

/// Clicking the ruler must land on the mark under the pointer, which means
/// seeking has to use the same inset span the marks are drawn across.
@Suite("Ruler seek mapping")
struct RulerSeekTests {
    private func time(atX x: Double) -> Double {
        TrackTimelineView.time(atX: x, width: 1000, duration: 60_000)
    }

    @Test("the left edge maps to the start")
    func leftEdgeIsStart() {
        #expect(time(atX: 0) == 0)
        // Anything inside the inset is still the start.
        #expect(time(atX: 5) == 0)
    }

    @Test("the right edge maps to the end")
    func rightEdgeIsEnd() {
        #expect(time(atX: 1000) == 60_000)
        #expect(time(atX: 995) == 60_000)
    }

    @Test("the middle maps to half way")
    func middleIsHalfway() {
        // 500 is the centre of the view and of the inset span alike.
        #expect(abs(time(atX: 500) - 30_000) < 1)
    }

    @Test("the mapping never leaves the track")
    func staysWithinTrack() {
        for x in stride(from: -50.0, through: 1050, by: 25) {
            let value = time(atX: x)
            #expect(value >= 0 && value <= 60_000, "out of range at x=\(x)")
        }
    }

    @Test("the mapping rises with position")
    func risesWithPosition() {
        #expect(time(atX: 200) < time(atX: 400))
        #expect(time(atX: 400) < time(atX: 800))
    }

    @Test("a zero-width ruler reports the start")
    func zeroWidthIsStart() {
        #expect(TrackTimelineView.time(atX: 10, width: 0, duration: 60_000) == 0)
    }
}
