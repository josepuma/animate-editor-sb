import Testing

@testable import StoryboardCore

@Suite("Sample schedule")
struct SampleScheduleTests {
    private func sample(_ time: Double, _ path: String = "a.wav") -> StoryboardSample {
        StoryboardSample(time: time, layer: .foreground, path: path, volume: 100)
    }

    private func schedule(_ times: [Double], at start: Double, inclusive: Bool = false) -> SampleSchedule {
        var s = SampleSchedule()
        s.samples = times.map { sample($0) }
        s.reset(at: start, inclusive: inclusive)
        return s
    }

    @Test("each sample fires once, in the half-open window (prev, current]")
    func halfOpen() {
        var s = schedule([1000, 1001], at: 999)
        #expect(s.advance(to: 1000, rate: 1, lookahead: 0).map(\.sample.time) == [1000])
        #expect(s.advance(to: 1001, rate: 1, lookahead: 0).map(\.sample.time) == [1001])
        #expect(s.advance(to: 1002, rate: 1, lookahead: 0).isEmpty)
    }

    @Test("a sample exactly at the cursor does not fire again")
    func noRefire() {
        var s = schedule([1000], at: 1000)
        #expect(s.advance(to: 1016, rate: 1, lookahead: 0).isEmpty)
    }

    @Test("an inclusive reset fires a sample sitting on the landing instant")
    func inclusiveReset() {
        var s = schedule([1000], at: 1000, inclusive: true)
        #expect(s.advance(to: 1000, rate: 1, lookahead: 0).count == 1)
        #expect(s.advance(to: 1016, rate: 1, lookahead: 0).isEmpty)
    }

    @Test("times before zero fire as the clock crosses them")
    func negativeTimes() {
        var s = schedule([-500], at: -600)
        #expect(s.advance(to: -520, rate: 1, lookahead: 0).isEmpty)
        #expect(s.advance(to: -480, rate: 1, lookahead: 0).count == 1)
    }

    @Test("times far past any track end still fire")
    func afterTrack() {
        var s = schedule([900_000], at: 899_000)
        #expect(s.advance(to: 900_010, rate: 1, lookahead: 0).count == 1)
    }

    @Test("seeking resets: nothing between the old and the new position fires")
    func seekSkips() {
        var s = schedule([1000, 5000, 9000], at: 0)
        _ = s.advance(to: 16, rate: 1, lookahead: 0)
        s.reset(at: 8000, inclusive: true)
        #expect(s.advance(to: 8016, rate: 1, lookahead: 0).isEmpty)
        #expect(s.advance(to: 9016, rate: 1, lookahead: 0).map(\.sample.time) == [9000])
    }

    @Test("a loop wrap fires nothing for the jump and the start fires next pass")
    func loopWrap() {
        var s = schedule([0, 5000], at: 4990)
        _ = s.advance(to: 5010, rate: 1, lookahead: 0)
        s.reset(at: 0, inclusive: true)
        #expect(s.advance(to: 16, rate: 1, lookahead: 0).map(\.sample.time) == [0])
    }

    @Test("lookahead hands over samples early with their delay")
    func lookahead() {
        var s = schedule([1050], at: 1000)
        let fired = s.advance(to: 1016, rate: 1, lookahead: 100)
        #expect(fired.count == 1)
        #expect(abs((fired.first?.delay ?? -1) - 34) < 1e-9)
        // already handed over: not again
        #expect(s.advance(to: 1032, rate: 1, lookahead: 100).isEmpty)
    }

    @Test("the delay is the song distance divided by the rate")
    func rateDelay() {
        var half = schedule([1050], at: 1000)
        var fast = schedule([1050], at: 1000)
        #expect(abs((half.advance(to: 1000, rate: 0.5, lookahead: 100).first?.delay ?? -1) - 100) < 1e-9)
        #expect(abs((fast.advance(to: 1000, rate: 2, lookahead: 100).first?.delay ?? -1) - 25) < 1e-9)
    }

    @Test("a sample a little late plays now, a very late one is dropped")
    func lateness() {
        var s = schedule([1000, 2000], at: 900, inclusive: true)
        // frame hiccup: jumps 40 ms past the first and 150 ms past the second
        let fired = s.advance(to: 1040, rate: 1, lookahead: 0)
        #expect(fired.count == 1)
        #expect(fired.first?.delay == 0)
        let late = s.advance(to: 2150, rate: 1, lookahead: 0)
        #expect(late.isEmpty)
    }

    @Test("ties keep their order")
    func ties() {
        var s = SampleSchedule()
        s.samples = [sample(10, "b.wav"), sample(10, "a.wav"), sample(5, "c.wav")]
        s.reset(at: 0, inclusive: false)
        #expect(s.advance(to: 20, rate: 1, lookahead: 0).map(\.sample.path) == ["c.wav", "b.wav", "a.wav"])
    }
}
