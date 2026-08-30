import CoreGraphics
import Testing

@testable import EditorShellFeature

@Suite("TimelineScale")
struct TimelineScaleTests {
    @Test("maps a span starting at zero")
    func mapsFromZero() {
        let scale = TimelineScale(range: 0...1000, width: 100)

        #expect(scale.x(of: 0) == 0)
        #expect(scale.x(of: 500) == 50)
        #expect(scale.x(of: 1000) == 100)
    }

    @Test("maps a span that opens before the track does")
    func mapsFromNegativeStart() {
        // A storyboard can begin before the first note. The origin is the start
        // of the span, not zero: assuming zero pushes every mark to the right
        // by however early the storyboard opens.
        let scale = TimelineScale(range: -500...1500, width: 100)

        #expect(scale.x(of: -500) == 0)
        #expect(scale.x(of: 500) == 50)
        #expect(scale.x(of: 1500) == 100)
    }

    @Test("time and position are inverses")
    func roundTrips() {
        let scale = TimelineScale(range: -250...1750, width: 200)

        for time in stride(from: -250.0, through: 1750, by: 250) {
            #expect(abs(scale.time(atX: scale.x(of: time)) - time) < 1e-9)
        }
    }

    @Test("a position outside the width clamps to the span")
    func clampsOutOfBounds() {
        let scale = TimelineScale(range: 0...1000, width: 100)

        #expect(scale.time(atX: -50) == 0)
        #expect(scale.time(atX: 150) == 1000)
    }

    @Test("a stretch of time has a width independent of where it sits")
    func spanWidthIgnoresOrigin() {
        // Widths are differences, so the origin must not enter into them —
        // subtracting it twice is what shrinks a clip drawn on a shifted span.
        let fromZero = TimelineScale(range: 0...1000, width: 100)
        let shifted = TimelineScale(range: -1000...0, width: 100)

        #expect(fromZero.width(of: 250) == shifted.width(of: 250))
    }

    @Test("a zero width yields no positions rather than dividing by it")
    func zeroWidthIsSafe() {
        let scale = TimelineScale(range: 0...1000, width: 0)

        #expect(scale.x(of: 500) == 0)
        #expect(scale.time(atX: 50) == 0)
    }
}

@Suite("TimelineScale — drag distances")
struct TimelineScaleDragTests {
    /// A window that does not start at zero, which is the case that catches
    /// formulas assuming an origin of 0.
    private let scale = TimelineScale(range: 2000...6000, width: 400)

    @Test("a distance converts to the time it covers")
    func distanceToDuration() {
        // 400pt spans 4000ms, so a quarter of the width is a quarter of the span.
        #expect(scale.duration(ofWidth: 100) == 1000)
    }

    /// The bug this pins: `time(atX:)` clamps to the visible span, so a
    /// leftward drag translation came back as 0 and a block could be dragged
    /// right but never back.
    @Test("a leftward distance converts to negative time")
    func negativeDistance() {
        #expect(scale.duration(ofWidth: -100) == -1000)
    }

    @Test("a distance beyond the width is not clamped")
    func beyondTheWindow() {
        #expect(scale.duration(ofWidth: 800) == 8000)
    }

    @Test("distance and width are inverses of each other")
    func roundTrip() {
        for span in [250.0, 1000, 4000, 9000] {
            #expect(abs(scale.duration(ofWidth: scale.width(of: span)) - span) < 1e-9)
        }
    }

    @Test("a zero-width timeline yields no duration rather than dividing by zero")
    func zeroWidth() {
        #expect(TimelineScale(range: 0...1000, width: 0).duration(ofWidth: 50) == 0)
    }
}
