import CoreGraphics
import Foundation

/// A track's span as it is drawn: where it sits on screen and how wide it reads.
struct VisibleSpan: Identifiable, Equatable {
    /// Position among the track's spans, which is what names the clip.
    let index: Int
    let start: CGFloat
    let width: CGFloat

    var id: Int { index }

    /// Narrower than this and a pill has no shape left to read.
    static let minimumWidth: CGFloat = 3

    /// The spans of a track, cropped to a visible window.
    ///
    /// Cropped rather than drawn whole and left to a clip shape: zoomed in, a
    /// span usually opens before the window does, and a pill offset to a
    /// negative position carries its whole width off the left edge with it —
    /// which looks like a clip disappearing while the sprites it stands for are
    /// still on screen.
    ///
    /// Spans lying entirely outside are dropped rather than clamped, or they
    /// collapse to the minimum width and pile up against whichever edge they
    /// fell off, reading as content where there is none.
    static func spans(
        of ranges: [ClosedRange<Double>],
        scale: TimelineScale,
    ) -> [VisibleSpan] {
        let window = scale.range

        return ranges.enumerated().compactMap { index, range in
            guard range.upperBound >= window.lowerBound,
                  range.lowerBound <= window.upperBound
            else { return nil }

            let start = max(0, scale.x(of: range.lowerBound))
            let end = min(scale.width, scale.x(of: range.upperBound))

            return VisibleSpan(
                index: index,
                start: start,
                width: max(minimumWidth, end - start),
            )
        }
    }
}
