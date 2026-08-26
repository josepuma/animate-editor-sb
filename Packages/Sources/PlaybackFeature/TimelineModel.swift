import Foundation
import StoryboardCore

/// Viewport and zoom state for the timeline.
///
/// Holds no SwiftUI types, so the mapping between time and screen position can
/// be tested directly.
@MainActor
@Observable
public final class TimelineModel {
    /// Milliseconds per point. Smaller is more zoomed in.
    public private(set) var msPerPoint: Double = 5

    /// Time at the centre of the detail view.
    public private(set) var centreTime: Double = 0

    /// Whether the viewport follows the playhead during playback.
    public var followsPlayhead = true

    /// Beat subdivisions per beat: 1, 2, 4, 8, 16.
    public var beatDivisor = 4 {
        didSet { beatDivisor = max(1, min(16, beatDivisor)) }
    }

    public private(set) var grid: BeatGrid?

    /// Fully zoomed in: fine detail for placing single frames.
    public static let minMsPerPoint: Double = 0.5
    /// Fully zoomed out: whole sections at a glance.
    public static let maxMsPerPoint: Double = 50

    public init() {}

    // ─── Content ─────────────────────────────────────────────────────────────

    public func setTiming(_ timing: BeatmapTimingData?) {
        grid = timing.map { BeatGrid(timing: $0, divisor: beatDivisor) }
    }

    /// Rebuilds the grid after the divisor changes.
    public func refreshGrid() {
        guard let timing = grid?.timing else { return }
        grid = BeatGrid(timing: timing, divisor: beatDivisor)
    }

    // ─── Viewport ────────────────────────────────────────────────────────────

    /// The time range visible in a detail view `width` points wide.
    public func visibleRange(width: Double) -> ClosedRange<Double> {
        let half = width / 2 * msPerPoint
        return (centreTime - half)...(centreTime + half)
    }

    /// Converts a time to an x offset within a view `width` points wide.
    public func x(for time: Double, width: Double) -> Double {
        let range = visibleRange(width: width)
        return (time - range.lowerBound) / msPerPoint
    }

    /// Converts an x offset back to a time.
    public func time(atX x: Double, width: Double) -> Double {
        visibleRange(width: width).lowerBound + x * msPerPoint
    }

    public func centre(on time: Double) {
        centreTime = time
    }

    /// Scrolls by `points`, as from a trackpad gesture.
    public func scroll(byPoints points: Double, duration: Double) {
        centreTime = min(max(0, centreTime + points * msPerPoint), duration)
    }

    // ─── Zoom ────────────────────────────────────────────────────────────────

    /// Multiplies the zoom, keeping `anchorTime` where it is on screen.
    ///
    /// Zooming about the pointer rather than the centre is what makes a
    /// timeline feel like it is being scrubbed rather than jumping.
    public func zoom(by factor: Double, anchorTime: Double? = nil, width: Double) {
        let anchor = anchorTime ?? centreTime
        let anchorX = x(for: anchor, width: width)

        msPerPoint = min(max(Self.minMsPerPoint, msPerPoint / factor), Self.maxMsPerPoint)

        // Restore the anchor to the same screen position under the new scale.
        centreTime = anchor - (anchorX - width / 2) * msPerPoint
    }

    public func zoomIn(width: Double, anchorTime: Double? = nil) {
        zoom(by: 1.4, anchorTime: anchorTime, width: width)
    }

    public func zoomOut(width: Double, anchorTime: Double? = nil) {
        zoom(by: 1 / 1.4, anchorTime: anchorTime, width: width)
    }

    public var canZoomIn: Bool { msPerPoint > Self.minMsPerPoint }
    public var canZoomOut: Bool { msPerPoint < Self.maxMsPerPoint }

    // ─── Labels ──────────────────────────────────────────────────────────────

    /// Spacing between time labels, chosen so they never crowd together.
    ///
    /// Steps through a 1-2-5 sequence, the same progression chart axes use.
    public func labelInterval() -> Double {
        let targetPoints: Double = 90
        let targetMs = targetPoints * msPerPoint

        let candidates: [Double] = [
            100, 250, 500,
            1_000, 2_000, 5_000,
            10_000, 15_000, 30_000,
            60_000, 120_000, 300_000,
        ]
        return candidates.first { $0 >= targetMs } ?? candidates[candidates.count - 1]
    }

    /// Formats a time as `m:ss` or `m:ss.h`, depending on the zoom.
    public func label(for time: Double) -> String {
        let totalSeconds = Int(time / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if labelInterval() < 1000 {
            let tenths = Int(time.truncatingRemainder(dividingBy: 1000) / 100)
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
