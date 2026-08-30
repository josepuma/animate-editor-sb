import Foundation

/// A seeded random source that produces the same stream everywhere, forever.
///
/// Deliberately not `SystemRandomNumberGenerator` or `Double.random`: neither
/// is reproducible across runs, and a particle field that comes out different
/// each evaluation means the preview and the exported `.osb` disagree — with
/// nothing on screen to suggest why.
///
/// SplitMix64, chosen because it is a handful of lines with no state beyond a
/// counter, and its output holds up under sequential seeds — effects derive
/// per-particle streams that way.
public struct EffectRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in [0, 1).
    ///
    /// Built from the top 53 bits, which is exactly what a `Double` can hold
    /// without rounding — taking the low bits instead would bias the result.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A value in [min, max).
    public mutating func between(_ minimum: Double, _ maximum: Double) -> Double {
        minimum + unit() * (maximum - minimum)
    }

    /// A value in [-spread, +spread].
    public mutating func symmetric(_ spread: Double) -> Double {
        between(-spread, spread)
    }

    /// An integer in [min, max].
    public mutating func integer(in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(span))
    }

    /// A generator for one item of a series, derived from this one's seed.
    ///
    /// Per-item streams keep particle *n* identical no matter how many
    /// particles come before it, so raising the count adds to the field
    /// instead of reshuffling it.
    ///
    /// The index is mixed rather than added. Adding leaves neighbouring seeds
    /// producing neighbouring streams — seeds 1 and 2 came out visually
    /// identical, because SplitMix64's own increment swamps a difference of
    /// one before the avalanche stage sees it.
    public func stream(_ index: Int) -> EffectRandom {
        var mixed = state ^ (UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15)
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return EffectRandom(seed: mixed ^ (mixed >> 31))
    }
}
