import CoreGraphics
import Testing
@testable import PlaybackFeature

/// The selection frame never vanishes under a gesture it is carrying.
///
/// Reported: shrinking a clip with a side handle until the frame disappeared,
/// then the frame never came back, on any clip. The frame stopped being drawn
/// below its minimum size mid-drag — and the handles carrying the drag went
/// with it, so the gesture never ended: the drag was never committed, its
/// shrink factor stayed applied to every box after it, and each one came out
/// too small to draw.
@Suite("Selection frame during a drag")
struct SelectionFrameDragTests {
    private let view = CGSize(width: 800, height: 600)

    @Test("at rest, a box too small to draw is not drawn")
    func restingTinyIsHidden() {
        #expect(SelectionBox.shown(CGRect(x: 100, y: 100, width: 3, height: 200), rotation: 0, in: view, isDragging: false) == nil)
    }

    @Test("under a gesture, the box stays — at least its minimum, where the clip is")
    func draggingTinyStays() throws {
        let raw = CGRect(x: 100, y: 100, width: 3, height: 200)
        let shown = try #require(SelectionBox.shown(raw, rotation: 0, in: view, isDragging: true))
        #expect(shown.width >= SelectionBox.minimumDraggedSize)
        #expect(abs(shown.midX - raw.midX) < 0.5, "centred on the clip")
        #expect(shown.height == 200, "the axis that is not shrinking keeps its size")
    }

    /// The same trap moving a clip off the stage: its measured box is
    /// nothing, and the grip carrying the drag must not unmount.
    @Test("under a gesture, a box off the stage is held at its edge")
    func draggingOffStageStays() throws {
        let shown = try #require(SelectionBox.shown(
            CGRect(x: 900, y: 100, width: 50, height: 50), rotation: 0, in: view, isDragging: true,
        ))
        #expect(shown.maxX <= view.width && shown.minX >= 0)
    }

    @Test("a box big enough is the held box, dragging or not")
    func normalUnchanged() {
        let raw = CGRect(x: 100, y: 100, width: 300, height: 200)
        #expect(SelectionBox.shown(raw, rotation: 0, in: view, isDragging: true) == SelectionBox.held(raw, rotation: 0, in: view))
        #expect(SelectionBox.shown(raw, rotation: 0, in: view, isDragging: false) == SelectionBox.held(raw, rotation: 0, in: view))
    }

    /// A drag left over from a gesture that never ended is dropped as soon as
    /// the selection changes — whatever stranded it.
    @Test("leftover drag state is dropped when nothing is dragging or waiting")
    func strandedIsDropped() {
        #expect(SelectionBox.isStranded(isDragging: false, awaitingCommit: false, moved: true))
        #expect(!SelectionBox.isStranded(isDragging: true, awaitingCommit: false, moved: true))
        #expect(!SelectionBox.isStranded(isDragging: false, awaitingCommit: true, moved: true))
        #expect(!SelectionBox.isStranded(isDragging: false, awaitingCommit: false, moved: false))
    }
}
