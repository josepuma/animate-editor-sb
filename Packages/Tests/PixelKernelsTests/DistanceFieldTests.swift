import Testing

@testable import PixelKernels

/// The distance transform the outline and ink lines are measured with.
///
/// Checked against brute force, not against a restated formula: a test that
/// rewrote the envelope would agree with any envelope.
@Suite("Distance field")
struct DistanceFieldTests {
    @Test("exact Euclidean distance to the nearest marked pixel")
    func matchesBruteForce() {
        let (w, h) = (23, 17)
        var marked = [Bool](repeating: false, count: w * h)
        for (x, y) in [(3, 4), (19, 2), (11, 15), (12, 15), (0, 16)] { marked[y * w + x] = true }

        let field = PixelKernels.distanceToNearest(marked, width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                var best = Double.infinity
                for j in 0..<h { for i in 0..<w where marked[j * w + i] {
                    best = min(best, (Double((x - i) * (x - i) + (y - j) * (y - j))).squareRoot())
                } }
                #expect(abs(field[y * w + x] - best) < 1e-9, "at \(x),\(y)")
            }
        }
    }

    @Test("a marked pixel is at distance zero")
    func markedIsZero() {
        let field = PixelKernels.distanceToNearest([false, true, false], width: 3, height: 1)
        #expect(field == [1, 0, 1])
    }
}
