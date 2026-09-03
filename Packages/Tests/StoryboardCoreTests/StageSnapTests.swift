import Foundation
import Testing

@testable import StoryboardCore

/// Placing something at the centre by eye is a thing nobody can do: a clip
/// lands at 319 or 322 and looks centred until it sits beside something that
/// really is.
@Suite("Stage snapping")
struct StageSnapTests {
    /// A 100×100 box, by its corners.
    private func box(at x: Double, _ y: Double) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (minX: x - 50, minY: y - 50, maxX: x + 50, maxY: y + 50)
    }

    @Test("a clip near the centre lands on it")
    func snapsToCentre() {
        // Four units short of centre, well inside the threshold.
        let result = StageSnap.adjust(box(at: 316, 240), by: (dx: 0, dy: 0))

        #expect(result.snappedX == StageSnap.Stage.centreX)
        #expect(abs(result.dx - 4) < 0.001, "expected a 4-unit nudge, got \(result.dx)")
    }

    /// Snapping that reaches too far takes the drag away from the hand.
    @Test("a clip far from a line is left alone")
    func leavesDistantClipsAlone() {
        let result = StageSnap.adjust(box(at: 200, 200), by: (dx: 0, dy: 0))

        #expect(result.snappedX == nil)
        #expect(result.snappedY == nil)
        #expect(result.dx == 0)
        #expect(result.dy == 0)
    }

    /// The drag is what moves the clip, so the test has to be against where it
    /// *lands* rather than where it started.
    @Test("the snap is measured after the drag, not before")
    func snapsWhereTheDragLands() {
        // Starts far away, dragged to just short of centre.
        let result = StageSnap.adjust(box(at: 100, 240), by: (dx: 217, dy: 0))

        #expect(result.snappedX == StageSnap.Stage.centreX)
        #expect(abs(result.dx - 220) < 0.001, "expected the drag corrected to 220")
    }

    /// All three are things people line up: a box is centred on the stage, but
    /// it is also pushed flush against an edge.
    @Test("edges snap as well as centres")
    func edgesSnap() {
        // Left edge two units from the stage's left.
        let result = StageSnap.adjust(box(at: -55, 240), by: (dx: 0, dy: 0))

        #expect(result.snappedX == StageSnap.Stage.minX)
    }

    /// A small clip can sit within reach of two lines at once, and the closer
    /// one is what the hand is aiming at.
    @Test("the nearest line wins")
    func nearestLineWins() {
        // A tiny box between the centre and a third, closer to the centre.
        let tiny = (minX: 318.0, minY: 239.0, maxX: 322.0, maxY: 241.0)
        let result = StageSnap.adjust(tiny, by: (dx: 0, dy: 0))

        #expect(result.snappedX == StageSnap.Stage.centreX)
    }

    /// Both axes snap independently — a letterbox bar is centred on one and
    /// flush on the other.
    @Test("the axes snap independently")
    func axesAreIndependent() {
        let result = StageSnap.adjust(box(at: 318, 200), by: (dx: 0, dy: 0))

        #expect(result.snappedX == StageSnap.Stage.centreX)
        #expect(result.snappedY == nil, "y was nowhere near a line")
    }

    /// Held off, a drag has to pass through exactly as it came.
    @Test("disabled snapping changes nothing")
    func disabledIsInert() {
        let result = StageSnap.adjust(box(at: 316, 240), by: (dx: 3, dy: 7), isEnabled: false)

        #expect(result.dx == 3)
        #expect(result.dy == 7)
        #expect(result.snappedX == nil)
        #expect(result.snappedY == nil)
    }

    /// The wide stage starts left of the frame — it is the 4:3 playfield with a
    /// margin either side. A snap built on `0...width` would put every line 107
    /// units off, which is exactly how a constant offset looks.
    @Test("the stage starts at -107, not at zero")
    func stageOriginIsNegative() {
        #expect(StageSnap.verticalLines.contains(-107))
        #expect(StageSnap.verticalLines.contains(747))
        #expect(StageSnap.Stage.maxX - StageSnap.Stage.minX == StageSnap.Stage.width)
    }

    /// The centre has to be the centre.
    @Test("the centre sits midway between the edges")
    func centreIsCentred() {
        let midX = (StageSnap.Stage.minX + StageSnap.Stage.maxX) / 2
        #expect(midX == StageSnap.Stage.centreX)
        #expect((StageSnap.Stage.minY + StageSnap.Stage.maxY) / 2 == StageSnap.Stage.centreY)
    }
}
