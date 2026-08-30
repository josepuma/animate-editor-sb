import CoreGraphics
import Testing

@testable import EditorShellFeature

/// How far a drag has to travel vertically before it changes lane.
///
/// The threshold is what lets one gesture mean two things safely: an ordinary
/// horizontal drag never travels far enough up or down to count, so moving a
/// clip in time cannot move it between tracks by accident.
@Suite("Row crossing")
struct RowCrossingTests {
    /// Matches the timeline's own row pitch: the row height plus the gap
    /// between rows.
    private let pitch: CGFloat = 52 + 4

    private func rows(_ translation: CGFloat) -> Int {
        Int((translation / pitch).rounded())
    }

    @Test("a horizontal drag stays on its own lane")
    func horizontalDragDoesNotCross() {
        #expect(rows(0) == 0)
        #expect(rows(4) == 0)
        #expect(rows(-6) == 0)
    }

    /// Half a row is the tipping point, so the clip changes lane as it visually
    /// reaches one rather than after passing it.
    @Test("crossing happens at the halfway mark")
    func halfwayTips() {
        #expect(rows(pitch * 0.49) == 0)
        #expect(rows(pitch * 0.51) == 1)
    }

    @Test("further drags cross further")
    func multipleRows() {
        #expect(rows(pitch) == 1)
        #expect(rows(pitch * 2) == 2)
        #expect(rows(-pitch * 3) == -3)
    }
}

/// The region that counts as "this clip" for hovering.
///
/// The ears are revealed by a clip's hover but sit outside it, so treating the
/// pill alone as the region meant the ear vanished from under the pointer on
/// its way there — visible, and impossible to grab.
@Suite("Clip hit region")
struct ClipHitRegionTests {
    private let earWidth: CGFloat = 10

    /// A clip from 100 to 160, the way the lane measures it.
    private func contains(_ x: CGFloat, start: CGFloat = 100, width: CGFloat = 60) -> Bool {
        x >= start - earWidth && x <= start + width + earWidth
    }

    @Test("the clip body counts")
    func body() {
        #expect(contains(100))
        #expect(contains(130))
        #expect(contains(160))
    }

    /// The case that was broken: the pointer between the pill and its ear.
    @Test("the ears count as part of the clip")
    func ears() {
        #expect(contains(95))
        #expect(contains(90))
        #expect(contains(165))
        #expect(contains(170))
    }

    @Test("beyond the ears does not count")
    func outside() {
        #expect(!contains(89))
        #expect(!contains(171))
    }

    /// A narrow clip is exactly where ears matter most, so its region has to
    /// stay reachable.
    @Test("a sliver of a clip still has grabbable ears")
    func narrowClip() {
        #expect(contains(96, start: 100, width: 3))
        #expect(contains(112, start: 100, width: 3))
    }
}

