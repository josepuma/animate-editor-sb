import Testing

@testable import ProjectBrowserFeature

/// The hero plays one project at random, and never the one it played last —
/// a "random" that keeps landing on the same map reads as not random at all.
@Suite("Featured picker")
struct FeaturedPickerTests {
    @Test("never repeats the last featured project when there is another")
    func avoidsLast() {
        var rng = SeededGenerator(seed: 1)
        for _ in 0 ..< 200 {
            let pick = FeaturedPicker.pick(from: ["a", "b", "c"], avoiding: "b", using: &rng)
            #expect(pick != "b")
            #expect(pick != nil)
        }
    }

    @Test("a single project is featured even if it was the last one")
    func singleProject() {
        var rng = SeededGenerator(seed: 2)
        #expect(FeaturedPicker.pick(from: ["a"], avoiding: "a", using: &rng) == "a")
    }

    @Test("nothing to feature without projects")
    func empty() {
        var rng = SeededGenerator(seed: 3)
        #expect(FeaturedPicker.pick(from: [String](), avoiding: nil, using: &rng) == nil)
    }

    @Test("every other project gets its turn")
    func spreads() {
        // A picker that always took the first candidate would pass the tests
        // above and still feature the same map forever.
        var rng = SeededGenerator(seed: 4)
        var seen: Set<String> = []
        for _ in 0 ..< 200 {
            if let pick = FeaturedPicker.pick(from: ["a", "b", "c", "d"], avoiding: "a", using: &rng) {
                seen.insert(pick)
            }
        }
        #expect(seen == ["b", "c", "d"])
    }
}

/// SplitMix64, so a failing case replays the same draws.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
