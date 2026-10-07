import Foundation
import Testing

@testable import StoryboardCore

/// The pure half of the stagger: unit indices in, ranks and delays out.
@Suite("Text stagger")
struct TextStaggerTests {
    private func ranks(
        _ units: [Int], _ order: String, wave: Double = 1, seed: UInt64 = 5,
    ) -> [Double] {
        var rng = EffectRandom(seed: seed)
        return TextStagger.ranks(units: units, order: order, waveAmount: wave, rng: &rng)
    }

    private let six = Array(0..<6)

    @Test("Start and End run in opposite directions")
    func startAndEnd() {
        #expect(ranks(six, "Start") == [0, 1, 2, 3, 4, 5])
        #expect(ranks(six, "End") == [5, 4, 3, 2, 1, 0])
    }

    /// S3.1: the ends first, the middle last — the mirror of Centre.
    @Test("Edges puts both ends first and the middle last")
    func edges() {
        let edges = ranks(six, "Edges")
        #expect(edges == [0, 1, 2, 2, 1, 0])
        #expect(edges != ranks(six, "Centre"))
        #expect(edges != ranks(six, "Start"))
        #expect(ranks(Array(0..<5), "Edges") == [0, 1, 2, 1, 0])
    }

    /// S3.3: no amplitude, no wave — the reading order.
    @Test("Wave at zero amplitude is Start")
    func waveZero() {
        #expect(ranks(six, "Wave", wave: 0) == ranks(six, "Start"))
    }

    /// S3.2: with amplitude the sequence surges and lags, so it is not
    /// monotonic, and it is neither Centre nor Edges.
    @Test("Wave is not monotonic and differs from the other orders")
    func waveIsNotMonotonic() {
        let units = Array(0..<12)
        let wave = ranks(units, "Wave", wave: 1.5)
        let steps = zip(wave, wave.dropFirst()).map { $1 - $0 }
        #expect(steps.contains { $0 < 0 }, "some unit must arrive before its predecessor")
        #expect(wave != ranks(units, "Start"))
        #expect(wave != ranks(units, "Centre"))
        #expect(wave != ranks(units, "Edges"))
        #expect(wave.min() == 0, "shifted so nothing is delayed below zero")
    }

    /// Within the parameter's 0…3 range the first unit is always the lowest,
    /// so the shift is only seen past it — the pure function takes any
    /// amplitude, and a negative rank would be a delay before the clip.
    @Test("Wave never ranks below zero")
    func waveFloor() {
        let wave = ranks(Array(0..<12), "Wave", wave: 10)
        #expect(wave.min() == 0)
        #expect(wave[0] > 0, "unit 0 is not the earliest at this amplitude")
    }

    /// Random is a permutation of the units, the same one every time.
    @Test("Random is a reproducible permutation of the units")
    func random() {
        let units = Array(0..<10)
        let first = ranks(units, "Random", seed: 8371)
        #expect(first == ranks(units, "Random", seed: 8371))
        #expect(first != ranks(units, "Random", seed: 1))
        #expect(first.sorted() == units.map(Double.init))
    }

    /// Glyphs of one unit share one rank, and the shuffle is over units.
    @Test("glyphs of a unit share a rank")
    func unitsShareRanks() {
        let units = [0, 0, 1, 1, 1, 2]
        let random = ranks(units, "Random", seed: 3)
        #expect(random[0] == random[1])
        #expect(random[2] == random[3] && random[3] == random[4])
        #expect(Set(random).count == 3)
        #expect(ranks(units, "End") == [2, 2, 1, 1, 1, 0])
    }

    // ─── Delays ──────────────────────────────────────────────────────────────

    @Test("Per Unit is a step per rank")
    func perUnit() {
        let delays = TextStagger.delays(
            ranks: [0, 1, 2, 2], mode: "Per Unit", stagger: 70, spread: 60, window: 1000,
        )
        #expect(delays == [0, 70, 140, 140])
    }

    /// S4.1: the last arrival is exactly `spread`% of the room, the first is 0.
    @Test("Spread lands the last unit at its share of the window")
    func spreadNormalises() {
        let delays = TextStagger.delays(
            ranks: [0, 1, 2, 3], mode: "Spread", stagger: 999, spread: 60, window: 2000,
        )
        #expect(delays.first == 0)
        #expect(abs(delays.last! - 0.6 * 2000) < 1e-9)
        #expect(delays == delays.sorted())
    }

    /// Even at 100% the last unit does not pass the window.
    @Test("Spread never passes the window")
    func spreadCap() {
        let delays = TextStagger.delays(
            ranks: [0, 1, 2, 3, 4], mode: "Spread", stagger: 0, spread: 100, window: 800,
        )
        #expect(delays.max()! <= 800)
    }

    /// S4.3: one unit has nothing to spread across.
    @Test("a single unit has no delay and no NaN")
    func singleUnit() {
        let delays = TextStagger.delays(
            ranks: [0, 0, 0], mode: "Spread", stagger: 50, spread: 100, window: 500,
        )
        #expect(delays == [0, 0, 0])
        #expect(delays.allSatisfy { $0.isFinite })
    }

    @Test("an empty window gives no delay")
    func emptyWindow() {
        let delays = TextStagger.delays(
            ranks: [0, 1, 2], mode: "Spread", stagger: 50, spread: 100, window: 0,
        )
        #expect(delays == [0, 0, 0])
    }
}
