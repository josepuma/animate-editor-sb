import CoreGraphics
import Foundation

/// How much of the storyboard the timeline shows, and which part.
///
/// Separate from `TimelineScale`, which maps a span to a width. This decides
/// what that span is: at rest the whole storyboard, zoomed in a window onto
/// part of it.
struct TimelineZoom: Equatable {
    /// What the view stores between frames.
    ///
    /// Only how far in and how far along — never the span itself. The span
    /// arrives in stages as a storyboard loads, and a stored copy goes stale:
    /// a window computed against yesterday's span puts the ruler and the clips
    /// on different timelines.
    struct State: Equatable {
        /// How much of the span is shown, from 1 (all of it) upwards.
        var magnification: Double = 1
        /// Where the window sits, as a fraction of the space it can travel.
        ///
        /// A fraction rather than a time so that zooming out does not slide the
        /// view: the same fraction of a wider window shows the same part of the
        /// track.
        var offset: Double = 0
    }

    /// The whole storyboard, in milliseconds.
    let full: ClosedRange<Double>
    var state: State

    /// Beyond this a pixel is a fraction of a millisecond, which is finer than
    /// anything a storyboard command is authored at.
    static let maximumMagnification: Double = 64
    /// Each press moves one step along the scale.
    static let step: Double = 1.6

    init(full: ClosedRange<Double>, state: State = State()) {
        self.full = full
        self.state = state
    }

    var magnification: Double { state.magnification }
    var offset: Double { state.offset }

    // ─── Visible span ────────────────────────────────────────────────────────

    /// The stretch of time on screen.
    var visible: ClosedRange<Double> {
        let width = fullDuration / magnification
        let travel = fullDuration - width
        let start = full.lowerBound + travel * offset

        return start...(start + width)
    }

    var fullDuration: Double {
        max(full.upperBound - full.lowerBound, 1)
    }

    var canZoomIn: Bool { magnification < Self.maximumMagnification }
    var canZoomOut: Bool { magnification > 1 }

    // ─── Zooming ─────────────────────────────────────────────────────────────

    /// Zooms in one step, keeping `anchor` where it is on screen.
    ///
    /// - Parameter anchor: the time to hold still, usually the playhead. Zoom
    ///   that always works from the middle throws away where the user was
    ///   looking, which is the whole reason they zoomed.
    mutating func zoomIn(around anchor: Double) {
        setMagnification(magnification * Self.step, around: anchor)
    }

    mutating func zoomOut(around anchor: Double) {
        setMagnification(magnification / Self.step, around: anchor)
    }

    mutating func reset() {
        state.magnification = 1
        state.offset = 0
    }

    mutating func setMagnification(_ value: Double, around anchor: Double) {
        let clamped = min(max(value, 1), Self.maximumMagnification)
        guard clamped != magnification else { return }

        // Where the anchor sits in the visible window right now, so it can be
        // put back in the same place afterwards.
        let previous = visible
        let previousWidth = previous.upperBound - previous.lowerBound
        let anchorFraction = previousWidth > 0
            ? (anchor - previous.lowerBound) / previousWidth
            : 0.5

        state.magnification = clamped

        let width = fullDuration / magnification
        let travel = fullDuration - width
        guard travel > 0 else {
            state.offset = 0
            return
        }

        let desiredStart = anchor - width * anchorFraction
        state.offset = min(max((desiredStart - full.lowerBound) / travel, 0), 1)
    }

    // ─── Panning ─────────────────────────────────────────────────────────────

    /// Slides the window by a fraction of its own width.
    mutating func pan(byFractionOfWindow fraction: Double) {
        let width = fullDuration / magnification
        let travel = fullDuration - width
        guard travel > 0 else { return }

        state.offset = min(max(offset + fraction * width / travel, 0), 1)
    }

    /// How close to the edge the playhead gets before the view follows it.
    ///
    /// Not the edge itself: a window that advances only once the playhead
    /// touches the boundary shows nothing of what is coming, which is what the
    /// eye is reading ahead for.
    private static let followMargin: Double = 0.15

    /// Keeps `time` in view as it advances.
    ///
    /// Pages forward rather than tracking continuously: a window that slides on
    /// every frame pins the playhead and moves the world around it, which is
    /// far harder to read than a view that holds still and jumps.
    mutating func follow(_ time: Double) {
        let window = visible
        let width = window.upperBound - window.lowerBound
        let travel = fullDuration - width
        guard travel > 0 else { return }

        let margin = width * Self.followMargin
        let comfortable = (window.lowerBound + margin)...(window.upperBound - margin)
        guard !comfortable.contains(time) else { return }

        // Landing a little in from the left leaves the moment just played still
        // visible, which is what makes the jump readable.
        let desiredStart = time - margin
        state.offset = min(max((desiredStart - full.lowerBound) / travel, 0), 1)
    }

    /// Brings `time` into view if it has scrolled off, centring on it.
    ///
    /// For jumps rather than playback: after a seek there is no direction of
    /// travel to lead, so the target sits in the middle.
    mutating func reveal(_ time: Double) {
        let window = visible
        guard !window.contains(time) else { return }

        let width = window.upperBound - window.lowerBound
        let travel = fullDuration - width
        guard travel > 0 else { return }

        let desiredStart = time - width / 2
        state.offset = min(max((desiredStart - full.lowerBound) / travel, 0), 1)
    }
}
