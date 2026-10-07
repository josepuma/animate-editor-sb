import Foundation

/// Who arrives when, for text.
///
/// Pure on purpose: no sprites, no context, only unit indices in and numbers
/// out. The order and the timing are the part of a text effect that grows axes
/// (units, new orders, a spread mode), and keeping them out of the evaluator
/// keeps both small enough to test without drawing anything.
enum TextStagger {
    /// A position per glyph in the order its **unit** arrives.
    ///
    /// `units[g]` is the dense unit index of glyph `g` — a word, a line, or the
    /// glyph itself — so every glyph of a unit shares one rank. Returned as
    /// numbers rather than a sorted list for the same reason the old order was:
    /// sprites stay in reading order, and that order is their draw order.
    ///
    /// Doubles because Wave produces fractional positions; for the integer
    /// orders `stagger * rank` has exactly the bits `stagger * Double(Int)` had.
    static func ranks(
        units: [Int],
        order: String,
        waveAmount: Double,
        rng: inout EffectRandom,
    ) -> [Double] {
        guard let last = units.max() else { return [] }
        let count = last + 1

        let perUnit: [Double]
        switch order {
        case "End":
            perUnit = (0..<count).map { Double(count - 1 - $0) }
        case "Centre":
            let middle = Double(count - 1) / 2
            perUnit = (0..<count).map { Double(Int(abs(Double($0) - middle).rounded())) }
        case "Edges":
            // The mirror of Centre: both ends first, the middle last.
            perUnit = (0..<count).map { Double(min($0, count - 1 - $0)) }
        case "Wave":
            // A sine riding on the reading order, so arrivals surge and lag
            // instead of marching. Period of six units; shifted so the earliest
            // is still zero — a negative rank would be a delay before the clip.
            let raw = (0..<count).map { Double($0) + waveAmount * sin(Double($0) * .pi / 3) }
            let floor = raw.min() ?? 0
            perUnit = raw.map { $0 - floor }
        case "Random":
            var positions = Array(0..<count)
            // Fisher-Yates over *units*, through the seeded stream, so the
            // preview and the exported file agree. With one glyph per unit this
            // is the draw sequence the glyph-level shuffle always made.
            for index in stride(from: count - 1, to: 0, by: -1) {
                let swap = rng.integer(in: 0...index)
                positions.swapAt(index, swap)
            }
            perUnit = positions.map(Double.init)
        default:
            perUnit = (0..<count).map(Double.init)
        }

        return units.map { perUnit[$0] }
    }

    /// The delay of each glyph, in milliseconds.
    ///
    /// `Per Unit` is a fixed step per rank, with no ceiling — a long text
    /// simply takes longer, as it always did. `Spread` states the stagger as a
    /// share of `window` instead, normalised by the highest rank, so the last
    /// unit lands at exactly `spread`% of the room and the whole line scales
    /// with the clip. `window` is what is left after the entrance and the exit
    /// have taken their time, which is what guarantees nobody arrives after
    /// the exit has begun.
    static func delays(
        ranks: [Double],
        mode: String,
        stagger: Double,
        spread: Double,
        window: Double,
    ) -> [Double] {
        if mode == "Spread" {
            let top = ranks.max() ?? 0
            // One unit has nothing to spread across, and dividing by a zero
            // rank would be NaN.
            guard top > 0 else { return ranks.map { _ in 0 } }
            return ranks.map { $0 / top * spread / 100 * window }
        }
        return ranks.map { stagger * $0 }
    }
}
