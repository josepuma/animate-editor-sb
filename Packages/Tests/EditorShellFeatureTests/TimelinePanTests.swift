import Testing

@testable import EditorShellFeature

@Suite("Timeline panning")
struct TimelinePanTests {
    private let full = 0.0...240_000.0

    /// The bug the rewrite fixes: as a fraction of the travel, a pan divided by
    /// `fullDuration - windowWidth`. Zoomed in, that divisor is nearly the whole
    /// track, so a small drag became a fraction that rounded away and moving
    /// about was a fight. In milliseconds the same drag means the same thing at
    /// every magnification.
    @Test("a pan moves the same distance at any magnification")
    func panIsScaleIndependent() {
        func moved(at magnification: Double) -> Double {
            var zoom = TimelineZoom(
                full: full,
                state: .init(magnification: magnification, start: 60_000),
            )
            let before = zoom.start
            zoom.pan(by: 500)
            return zoom.start - before
        }

        #expect(abs(moved(at: 2) - 500) < 0.001)
        #expect(abs(moved(at: 64) - 500) < 0.001)
    }

    /// Zoomed all the way in, a window is a fraction of a second wide — and a
    /// pan of a few hundred milliseconds has to be visible rather than lost.
    @Test("a small pan survives a large zoom")
    func smallPanSurvivesLargeZoom() {
        var zoom = TimelineZoom(
            full: full,
            state: .init(magnification: 64, start: 100_000),
        )
        let before = zoom.visible

        zoom.pan(by: 100)

        #expect(zoom.visible.lowerBound > before.lowerBound)
    }

    @Test("the window is held inside the span")
    func windowStaysInside() {
        var zoom = TimelineZoom(full: full, state: .init(magnification: 4, start: 0))

        zoom.pan(by: -999_999)
        #expect(zoom.start >= full.lowerBound - 0.001)

        zoom.pan(by: 999_999)
        #expect(zoom.visible.upperBound <= full.upperBound + 0.001)
    }

    /// Zooming holds whatever the anchor was looking at, which is the whole
    /// reason for zooming there rather than in the middle.
    @Test("zooming keeps its anchor in place")
    func zoomKeepsItsAnchor() {
        var zoom = TimelineZoom(full: full, state: .init(magnification: 2, start: 60_000))
        let anchor = 90_000.0
        let before = zoom.visible
        let fractionBefore = (anchor - before.lowerBound)
            / (before.upperBound - before.lowerBound)

        zoom.setMagnification(8, around: anchor)

        let after = zoom.visible
        let fractionAfter = (anchor - after.lowerBound) / (after.upperBound - after.lowerBound)
        #expect(abs(fractionAfter - fractionBefore) < 0.01)
    }

    @Test("fully zoomed out shows the whole span")
    func resetShowsEverything() {
        var zoom = TimelineZoom(full: full, state: .init(magnification: 16, start: 90_000))
        zoom.reset()

        #expect(zoom.visible.lowerBound == full.lowerBound)
        #expect(abs(zoom.visible.upperBound - full.upperBound) < 0.001)
    }

    /// A screenful is what a keyboard step means, whatever the magnification.
    @Test("a fractional pan moves by a share of the window")
    func fractionalPanMovesAScreenful() {
        var zoom = TimelineZoom(full: full, state: .init(magnification: 4, start: 60_000))
        let window = zoom.windowDuration

        zoom.pan(byFractionOfWindow: 0.5)

        #expect(abs((zoom.start - 60_000) - window / 2) < 0.001)
    }
}

@Suite("Timeline window bounds")
struct TimelineWindowTests {
    private let full = 0.0...65_799.0

    /// Clamping on read while storing raw values lets the stored one drift far
    /// outside the span — and it comes back the moment the window changes size,
    /// because a different width clamps to a different place. Scrolling past
    /// the end and then zooming put the view before zero, and every clip with
    /// it.
    @Test("panning past the end does not poison the stored start")
    func panIsClampedAsItIsStored() {
        var zoom = TimelineZoom(full: full, state: .init(magnification: 5, start: 0))

        // Well past the end, many times over.
        for _ in 0..<20 { zoom.pan(by: 100_000) }
        // Then back out, which changes the window's width.
        zoom.setMagnification(1, around: 0)

        #expect(zoom.visible.lowerBound >= full.lowerBound - 0.001)
        #expect(zoom.visible.upperBound <= full.upperBound + 0.001)
    }

    @Test("panning before the start is held at zero")
    func panBeforeStartIsHeld() {
        var zoom = TimelineZoom(full: full, state: .init(magnification: 5, start: 30_000))

        for _ in 0..<20 { zoom.pan(by: -100_000) }

        #expect(zoom.visible.lowerBound == full.lowerBound)
    }

    /// A window wider than the span belongs at its beginning, not before it:
    /// with the bounds applied the other way round, an upper bound smaller than
    /// the lower one wins.
    @Test("a window wider than the span starts at the beginning")
    func oversizedWindowStartsAtZero() {
        let zoom = TimelineZoom(full: 0...1_000, state: .init(magnification: 1, start: -5_000))

        #expect(zoom.start == 0)
    }
}
