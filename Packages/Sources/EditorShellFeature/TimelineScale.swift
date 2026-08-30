import CoreGraphics
import Foundation

/// Maps between storyboard time and a position along the timeline.
///
/// One type rather than the same `time / duration * width` written at every
/// call site: the timeline does not start at zero. A storyboard can open before
/// the first note, so the span has an origin of its own, and a formula that
/// assumes zero puts everything it draws out of step with everything else.
struct TimelineScale: Equatable {
    /// The span the timeline covers, in milliseconds.
    let range: ClosedRange<Double>
    /// The width that span is drawn across.
    let width: CGFloat

    init(range: ClosedRange<Double>, width: CGFloat) {
        self.range = range
        self.width = width
    }

    var duration: Double {
        max(range.upperBound - range.lowerBound, 1)
    }

    /// Where `time` falls along the timeline.
    func x(of time: Double) -> CGFloat {
        guard width > 0 else { return 0 }
        return CGFloat((time - range.lowerBound) / duration) * width
    }

    /// What time sits at `x`, clamped to the span.
    func time(atX x: CGFloat) -> Double {
        guard width > 0 else { return range.lowerBound }
        let ratio = min(max(x / width, 0), 1)
        return range.lowerBound + Double(ratio) * duration
    }

    /// How wide a stretch of time is on screen.
    func width(of span: Double) -> CGFloat {
        guard width > 0 else { return 0 }
        return CGFloat(span / duration) * width
    }
}
