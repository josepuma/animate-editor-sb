import Testing

@testable import EditorShellFeature

@Suite("TimelineZoom")
struct TimelineZoomTests {
    private func zoom(_ range: ClosedRange<Double> = 0...100_000) -> TimelineZoom {
        TimelineZoom(full: range)
    }

    @Test("at rest the whole storyboard is visible")
    func restShowsEverything() {
        let z = zoom()

        #expect(z.visible == 0...100_000)
        #expect(!z.canZoomOut)
        #expect(z.canZoomIn)
    }

    @Test("zooming in narrows the window")
    func zoomInNarrows() {
        var z = zoom()
        z.zoomIn(around: 50_000)

        let width = z.visible.upperBound - z.visible.lowerBound
        #expect(width < 100_000)
        #expect(z.canZoomOut)
    }

    @Test("the anchor stays where it was on screen")
    func anchorHolds() {
        // Zoom that recentres on the middle throws away the part being looked
        // at, which is the reason for zooming in the first place.
        var z = zoom()
        z.setMagnification(4, around: 25_000)

        let window = z.visible
        let fraction = (25_000 - window.lowerBound) / (window.upperBound - window.lowerBound)

        // A quarter of the way through the full span, held at the same
        // position within the narrower window.
        #expect(abs(fraction - 0.25) < 0.01)
    }

    @Test("the window never leaves the storyboard")
    func windowStaysInBounds() {
        var z = zoom()
        z.setMagnification(8, around: 0)
        #expect(z.visible.lowerBound >= 0)

        z.setMagnification(8, around: 100_000)
        #expect(z.visible.upperBound <= 100_000)
    }

    @Test("zooming out all the way restores the full span")
    func zoomOutRestores() {
        var z = zoom()
        z.setMagnification(16, around: 30_000)

        for _ in 0..<20 {
            z.zoomOut(around: 30_000)
        }

        #expect(z.visible == 0...100_000)
    }

    @Test("magnification is bounded at both ends")
    func magnificationClamps() {
        var z = zoom()

        z.setMagnification(1000, around: 0)
        #expect(z.magnification == TimelineZoom.maximumMagnification)

        z.setMagnification(0.01, around: 0)
        #expect(z.magnification == 1)
    }

    @Test("a span opening before zero zooms like any other")
    func handlesNegativeStart() {
        // A storyboard can start before the track. The window is measured from
        // the span's own beginning, not from zero.
        var z = zoom(-5000...95_000)
        z.setMagnification(2, around: -5000)

        #expect(z.visible.lowerBound == -5000)
    }

    @Test("panning slides the window without resizing it")
    func panKeepsWidth() {
        var z = zoom()
        z.setMagnification(4, around: 50_000)

        let before = z.visible
        z.pan(byFractionOfWindow: 0.5)
        let after = z.visible

        #expect(after.lowerBound > before.lowerBound)
        #expect(
            abs((after.upperBound - after.lowerBound) - (before.upperBound - before.lowerBound))
                < 1e-6,
        )
    }

    @Test("revealing a time already on screen changes nothing")
    func revealLeavesVisibleTimesAlone() {
        // Otherwise the window would creep on every frame of playback rather
        // than letting the playhead cross it.
        var z = zoom()
        z.setMagnification(4, around: 50_000)

        let before = z.visible
        z.reveal(before.lowerBound + 100)

        #expect(z.visible == before)
    }

    @Test("revealing a time off screen brings it back")
    func revealScrollsToOffscreenTimes() {
        var z = zoom()
        z.setMagnification(4, around: 10_000)

        z.reveal(90_000)
        #expect(z.visible.contains(90_000))
    }

    // ─── Following ───────────────────────────────────────────────────────────

    @Test("following leaves a playhead in the middle alone")
    func followIgnoresTheMiddle() {
        // Otherwise the window slides on every frame, pinning the playhead and
        // moving the world around it.
        var z = zoom()
        z.setMagnification(4, around: 50_000)

        let before = z.visible
        z.follow((before.lowerBound + before.upperBound) / 2)

        #expect(z.visible == before)
    }

    @Test("following pages forward before the playhead reaches the edge")
    func followPagesAhead() {
        // Waiting for the boundary itself shows nothing of what is coming,
        // which is what the eye reads ahead for.
        var z = zoom()
        z.setMagnification(4, around: 20_000)

        let before = z.visible
        let width = before.upperBound - before.lowerBound
        // Just inside the right edge, but within the margin.
        z.follow(before.upperBound - width * 0.05)

        #expect(z.visible.lowerBound > before.lowerBound)
    }

    @Test("following keeps the playhead visible")
    func followKeepsPlayheadOnScreen() {
        var z = zoom()
        z.setMagnification(8, around: 0)

        for time in stride(from: 0.0, through: 100_000, by: 1000) {
            z.follow(time)
            #expect(z.visible.contains(time), "lost the playhead at \(time)")
        }
    }

    @Test("following stops at the end rather than scrolling past it")
    func followStopsAtTheEnd() {
        var z = zoom()
        z.setMagnification(4, around: 100_000)

        z.follow(100_000)
        #expect(z.visible.upperBound <= 100_000)
    }
}
