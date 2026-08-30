import CoreGraphics
import DesignSystem
import Testing

@testable import EditorShellFeature

@Suite("Timeline geometry")
@MainActor
struct TimelineGeometryTests {
    @Test("content starts past the header and its gap")
    func contentOriginClearsTheHeader() {
        // The blocks begin where the header ends, not where the header starts:
        // an origin that forgets the gap slides every block back underneath the
        // track's own name and toggles.
        #expect(
            TrackTimelineView.contentOrigin
                == TrackTimelineView.headerWidth + Theme.Spacing.snug,
        )
    }

    @Test("content width and origin describe the same span")
    func widthAndOriginAgree() {
        // The ruler measures the span, the rows fill it and the playhead is
        // positioned along it. Three formulas that disagree by the width of a
        // gap put the playhead beside the mark it is passing.
        //
        // Measured inside the panel's padding: the reader sits under it, so the
        // width it reports already excludes the inset. Subtracting it again
        // here is what left the ruler short of the blocks beneath it.
        let inner: CGFloat = 1000

        #expect(
            TrackTimelineView.contentWidth(in: inner)
                == inner - TrackTimelineView.contentOrigin,
        )
    }

    @Test("a panel narrower than its own chrome yields no content")
    func narrowPanelClampsToZero() {
        // A negative width would flip the geometry rather than simply vanish.
        #expect(TrackTimelineView.contentWidth(in: 10) == 0)
    }
}
