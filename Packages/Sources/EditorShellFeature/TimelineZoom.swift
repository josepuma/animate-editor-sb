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

        /// Where the window starts, in milliseconds.
        ///
        /// A time, not a fraction of the travel.
        ///
        /// As a fraction every pan divided by `fullDuration - windowWidth`, and
        /// at high magnification that divisor is nearly the whole track: a
        /// pixel of drag became a fraction so small it rounded away, and moving
        /// about while zoomed in was a fight. In milliseconds a pan is the same
        /// arithmetic at every magnification — the window simply starts
        /// somewhere else.
        var start: Double = 0
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

    /// Where the window begins, held inside the span.
    var start: Double { held(state.start) }

    /// Holds a start inside the span.
    ///
    /// `max` last, so a window wider than the span lands at its beginning
    /// rather than before it: with the two the other way round, an upper bound
    /// smaller than the lower one wins and the view starts left of zero.
    private func held(_ value: Double) -> Double {
        max(full.lowerBound, min(value, full.upperBound - windowDuration))
    }

    /// How much time the window covers.
    var windowDuration: Double { fullDuration / magnification }

    // ─── Visible span ────────────────────────────────────────────────────────

    /// The stretch of time on screen.
    var visible: ClosedRange<Double> {
        start...(start + windowDuration)
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
        state.start = full.lowerBound
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

        // The anchor keeps its place on screen, so the window starts wherever
        // puts it back there.
        state.start = held(anchor - windowDuration * anchorFraction)
    }

    // ─── Panning ─────────────────────────────────────────────────────────────

    /// Slides the window by a fraction of its own width.
    mutating func pan(byFractionOfWindow fraction: Double) {
        state.start = held(start + windowDuration * fraction)
    }

    /// Slides the window by a length of time.
    ///
    /// What a scroll or a drag actually knows: so many pixels, converted once
    /// through the scale. The fraction form above is for the keyboard, where a
    /// step means "a screenful" rather than a distance.
    mutating func pan(by milliseconds: Double) {
        // Clamped as it is stored, not only as it is read.
        //
        // Reading through a clamp while storing raw values lets the stored one
        // drift far outside the span — and it comes back the moment the window
        // changes size, because a different width clamps to a different place.
        // Scrolling past the end and then zooming put the view before zero.
        state.start = held(start + milliseconds)
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
        guard magnification > 1 else { return }

        let margin = width * Self.followMargin
        let comfortable = (window.lowerBound + margin)...(window.upperBound - margin)
        guard !comfortable.contains(time) else { return }

        // Landing a little in from the left leaves the moment just played still
        // visible, which is what makes the jump readable.
        state.start = held(time - margin)
    }

    /// Brings `time` into view if it has scrolled off, centring on it.
    ///
    /// For jumps rather than playback: after a seek there is no direction of
    /// travel to lead, so the target sits in the middle.
    mutating func reveal(_ time: Double) {
        let window = visible
        guard !window.contains(time) else { return }

        state.start = held(time - windowDuration / 2)
    }
}
