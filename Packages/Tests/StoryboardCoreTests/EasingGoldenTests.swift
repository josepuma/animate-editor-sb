import Foundation
import Testing

@testable import StoryboardCore

/// Golden values captured from the TypeScript implementation
/// (`app/lib/engine/easing.ts`) via `scripts/gen-easing-golden.mjs`.
private struct EasingGolden: Decodable {
    let description: String
    let samples: [Double]
    let curves: [String: [Double]]
}

private func loadGolden() throws -> EasingGolden {
    let url = try #require(
        Bundle.module.url(forResource: "easing-golden", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "easing-golden", withExtension: "json"),
        "easing-golden.json fixture is missing from the test bundle",
    )
    return try JSONDecoder().decode(EasingGolden.self, from: Data(contentsOf: url))
}

@Suite("Easing — parity with the TypeScript implementation")
struct EasingGoldenTests {
    /// Tolerance for cross-language float comparison. JavaScript numbers and
    /// Swift `Double` are both IEEE-754 binary64, so differences come only from
    /// libm implementations of `sin`/`cos`/`pow`.
    static let tolerance = 1e-12

    @Test("every easing curve matches the TypeScript output")
    func allCurvesMatchGolden() throws {
        let golden = try loadGolden()

        for easing in Easing.allCases {
            let expected = try #require(
                golden.curves[String(easing.rawValue)],
                "fixture has no curve for easing \(easing.rawValue)",
            )
            #expect(
                expected.count == golden.samples.count,
                "curve \(easing.rawValue) has \(expected.count) values for \(golden.samples.count) samples",
            )

            for (index, t) in golden.samples.enumerated() {
                let actual = applyEasing(easing, t)
                let want = expected[index]
                let delta = abs(actual - want)
                #expect(
                    delta <= Self.tolerance,
                    """
                    easing \(easing) (id \(easing.rawValue)) at t=\(t): \
                    got \(actual), expected \(want), delta \(delta)
                    """,
                )
            }
        }
    }

    @Test("the fixture covers all 35 osu! easings")
    func fixtureCoversEveryEasing() throws {
        let golden = try loadGolden()
        #expect(golden.curves.count == 35)
        #expect(Easing.allCases.count == 35)
    }

    @Test("progress is clamped outside [0, 1]")
    func clampsOutOfRangeProgress() {
        for easing in Easing.allCases {
            #expect(applyEasing(easing, -0.5) == 0)
            #expect(applyEasing(easing, 0) == 0)
            #expect(applyEasing(easing, 1) == 1)
            #expect(applyEasing(easing, 1.5) == 1)
        }
    }

    @Test("unknown easing IDs fall back to linear")
    func unknownEasingFallsBackToLinear() {
        #expect(Easing(rawValueOrLinear: 99) == .linear)
        #expect(Easing(rawValueOrLinear: -1) == .linear)
        #expect(Easing(rawValueOrLinear: 17) == .sineInOut)
    }

    @Test("easedLerp interpolates between the endpoints")
    func easedLerpInterpolates() {
        #expect(easedLerp(0, 100, 0, .linear) == 0)
        #expect(easedLerp(0, 100, 1, .linear) == 100)
        #expect(abs(easedLerp(0, 100, 0.5, .linear) - 50) < 1e-12)
        // Descending ranges must work too — fades commonly go 1 → 0.
        #expect(abs(easedLerp(1, 0, 0.5, .linear) - 0.5) < 1e-12)
    }
}
