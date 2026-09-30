import Testing

@testable import StoryboardCore

/// `CommandTrack.resolve` must pick the same command as the plain backward
/// scan it replaced, for every track shape and every query time. The scan is
/// kept here, verbatim in behaviour, as the oracle.
@Suite("CommandTrack resolve")
struct CommandTrackResolveTests {
    private struct SplitMix {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        /// Integer-valued doubles in `0...bound`, so equal starts and ends
        /// (the tie-break cases) actually happen.
        mutating func whole(_ bound: Int) -> Double {
            Double(Int(next() % UInt64(bound + 1)))
        }
    }

    /// The pre-change algorithm, returning an index so identity can be compared.
    private static func reference(_ commands: [Command], at time: Double, upperBound ub: Int?) -> Int? {
        guard !commands.isEmpty else { return nil }
        guard let ub else { return 0 }
        var best: Int?
        for index in stride(from: ub, through: 0, by: -1) {
            let command = commands[index]
            if time <= command.endTime { return index }
            if best == nil
                || command.endTime > commands[best!].endTime
                || (command.endTime == commands[best!].endTime
                    && command.startTime > commands[best!].startTime)
            {
                best = index
            }
        }
        return best ?? 0
    }

    /// Fades whose start value is a unique id, so a wrong pick is visible even
    /// when two commands share every timing field.
    private static func makeTrack(count: Int, span: Int, maxLength: Int, seed: UInt64) -> CommandTrack {
        var random = SplitMix(state: seed)
        var commands: [Command] = []
        for id in 0..<count {
            let start = random.whole(span)
            // Zero-length commands and commands spanning everything both occur.
            let length = random.next() % 11 == 0 ? Double(span * 2) : random.whole(maxLength)
            commands.append(Command(
                easing: .linear, startTime: start, endTime: start + length,
                payload: .fade(start: Double(id), end: 0),
            ))
        }
        return CommandTracks(commands).fade
    }

    @Test("matches the backward scan on seeded random tracks")
    func equivalence() throws {
        var checked = 0
        for seed in 1...300 as ClosedRange<UInt64> {
            var shape = SplitMix(state: seed &* 7919)
            let count = 1 + Int(shape.next() % 60)
            let span = 5 + Int(shape.next() % 80)
            let maxLength = Int(shape.next() % 30)
            let track = Self.makeTrack(count: count, span: span, maxLength: maxLength, seed: seed)

            // Every whole time across the span (boundaries hit exactly), plus
            // before-first, after-last and off-grid instants.
            var times = (-3...(span * 3 + 3)).map(Double.init)
            times += [-0.5, 0.5, Double(span) + 0.25, -1e9, 1e9]

            for time in times {
                let expected = Self.reference(
                    track.commands, at: time, upperBound: track.upperBound(at: time))
                let actual = track.resolvedIndex(at: time)
                #expect(actual == expected, "seed \(seed) time \(time): \(String(describing: actual)) != \(String(describing: expected))")
                checked += 1
            }
        }
        #expect(checked > 10_000)
    }

    @Test("an unindexed track still resolves identically")
    func fallbackEquivalence() {
        var track = Self.makeTrack(count: 40, span: 30, maxLength: 8, seed: 99)
        track = CommandTrack(commands: track.commands)  // no prefix index
        #expect(track.maxEnd.isEmpty)
        for time in stride(from: -2.0, through: 100.0, by: 0.5) {
            #expect(track.resolvedIndex(at: time)
                == Self.reference(track.commands, at: time, upperBound: track.upperBound(at: time)))
        }
    }

    @Test("a query in a hold gap does no scanning on a 50,000-command track")
    func gapIsConstantWork() {
        // Hops: each command runs 10ms then holds 90ms until the next.
        var commands: [Command] = []
        for index in 0..<50_000 {
            let start: Double = Double(index) * 100
            commands.append(Command(
                easing: .linear, startTime: start, endTime: start + 10,
                payload: .fade(start: Double(index), end: 0),
            ))
        }
        let track = CommandTracks(commands).fade

        var steps = 0
        let gapTime = Double(40_000 * 100 + 50)
        let index = track.resolvedIndex(at: gapTime, steps: &steps)
        #expect(index == 40_000)
        #expect(steps == 0)

        // Same query without the index is the O(n) walk this fix removed —
        // proves the counter measures what it claims to.
        let plain = CommandTrack(commands: track.commands)
        var plainSteps = 0
        _ = plain.resolvedIndex(at: gapTime, steps: &plainSteps)
        #expect(plainSteps == 40_001)

        // Active case: the winner is the latest command, found immediately.
        var activeSteps = 0
        _ = track.resolvedIndex(at: Double(40_000 * 100 + 5), steps: &activeSteps)
        #expect(activeSteps <= 2)
    }

    @Test("ties on endTime and startTime hold the higher index")
    func tieBreak() {
        // Three identical timings, none active at t=20: the old scan met index
        // 2 first and only replaced on strict improvement.
        let commands = (0..<3).map { id in
            Command(easing: .linear, startTime: 0, endTime: 10,
                    payload: .fade(start: Double(id), end: 0))
        }
        let track = CommandTracks(commands).fade
        #expect(track.resolvedIndex(at: 20) == 2)
    }
}
