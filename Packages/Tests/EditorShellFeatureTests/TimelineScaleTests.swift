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
