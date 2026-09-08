import Foundation
import StoryboardCore

/// A reference-shaped wrapper over ``EffectRandom``, for handing to JavaScript.
///
/// `EffectRandom` is a value type whose `next()` mutates, which a JS-facing
/// block cannot hold: the block captures, and a captured copy would restart the
/// stream on every call — every particle landing on the same "random" number.
///
/// It wraps the existing generator rather than reimplementing SplitMix64.
/// Two copies of the same maths drift, and this codebase has already paid for
/// deriving a stream two different ways: seeds 1 and 2 produced visually
/// identical fields because an index was added to a seed instead of mixed into
/// it, and changing the seed appeared to do nothing at all.
final class RandomStream {
    private var generator: EffectRandom

    init(seed: UInt64) {
        generator = EffectRandom(seed: seed)
    }

    /// A value in [0, 1).
    func next() -> Double {
        generator.unit()
    }
}
