import CoreGraphics
import Testing

@testable import EditorShellFeature

@Suite("Visible spans")
struct VisibleSpanTests {
    private let scale = TimelineScale(range: 10_000...20_000, width: 1000)

    private func spans(_ ranges: [ClosedRange<Double>]) -> [VisibleSpan] {
        VisibleSpan.spans(of: ranges, scale: scale)
    }

    @Test("a span inside the window keeps its own position")
    func insideIsUnchanged() {
        let result = spans([12_000...14_000])

        #expect(result.count == 1)
        #expect(abs(result[0].start - 200) < 0.01)
        #expect(abs(result[0].width - 200) < 0.01)
    }

    @Test("a span opening before the window is cropped, not moved")
    func cropsAtTheLeftEdge() {
        // Zoomed in, most spans start before the window does. Offsetting one to
        // a negative position carries its whole width off screen with it, which
        // is a clip vanishing while its sprites are still playing.
        let result = spans([0...15_000])

        #expect(result.count == 1)
        #expect(result[0].start == 0)
        #expect(abs(result[0].width - 500) < 0.01)
    }

    @Test("a span running past the window is cropped at the right")
    func cropsAtTheRightEdge() {
        let result = spans([15_000...90_000])

        #expect(result.count == 1)
        #expect(abs(result[0].start - 500) < 0.01)
        #expect(abs(result[0].width - 500) < 0.01)
    }

    @Test("a span wider than the window fills it")
    func spanWiderThanWindow() {
        let result = spans([0...90_000])

        #expect(result.count == 1)
        #expect(result[0].start == 0)
        #expect(abs(result[0].width - 1000) < 0.01)
    }

    @Test("spans entirely outside the window are dropped")
    func outsideIsDropped() {
        // Kept, they collapse to the minimum pill width and pile up against
        // whichever edge they fell off — clips that read as content where there
        // is none.
        #expect(spans([0...5000]).isEmpty)
        #expect(spans([30_000...40_000]).isEmpty)
    }

    @Test("a span touching the edge is kept")
    func touchingIsKept() {
        #expect(spans([5000...10_000]).count == 1)
        #expect(spans([20_000...25_000]).count == 1)
    }

    @Test("spans keep their index so the labels stay right")
    func indicesSurviveFiltering() {
        // The label reads "Background 2", counted among all the track's spans —
        // dropping one off screen must not renumber the rest.
        let result = spans([
            0...5000,          // before the window
            12_000...13_000,   // inside
            30_000...40_000,   // after
            14_000...15_000,   // inside
        ])

        #expect(result.map(\.index) == [1, 3])
    }

    @Test("a moment-long span still has a pill to see")
    func minimumWidth() {
        let result = spans([15_000...15_001])

        #expect(result.count == 1)
        #expect(result[0].width >= 3)
    }
}
