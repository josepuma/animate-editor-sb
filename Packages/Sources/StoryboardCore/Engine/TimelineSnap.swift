import Foundation

/// Pulls a clip dragged along the timeline onto the beat.
///
/// In a rhythm game a clip that starts twelve milliseconds after the kick
/// starts *late*, and nobody can land on a beat by eye at any zoom where the
/// whole song fits on screen. The map already declares where every beat is, so
/// the timeline offers them the way the stage offers its centre.
///
/// Magnetic rather than quantised: an edge snaps only within `threshold` of a
/// target. Zoomed out, beats sit closer together than the threshold and every
/// drop lands on one; zoomed in, the hand is free between them — which is what
/// placing something on an off-beat swell needs.
///
/// Beats are not the only thing worth lining up with. Other clips' edges and
/// the playhead are passed in as `anchors`, so a clip can end exactly where the
/// next begins, or start where the playhead was parked on purpose.
public enum TimelineSnap {
    /// Where a dragged edge lands, and the time it caught, if any — so the
    /// timeline can draw the line it landed on.
    public struct Snap: Sendable, Equatable {
        public var time: Double
        public var guide: Double?

        public init(time: Double, guide: Double? = nil) {
            self.time = time
            self.guide = guide
        }
    }

    /// How close an edge has to come, in points, before it snaps.
    ///
    /// Points rather than milliseconds so the pull feels the same at any zoom;
    /// the caller converts through its own scale.
    public static let thresholdPoints: Double = 8

    /// Snaps one edge — what resizing a clip moves.
    ///
    /// - Parameter isEnabled: passing `false` returns the edge untouched, so
    ///   the caller can offer the usual "hold ⌘ to disable" without a second path.
    public static func edge(
        _ time: Double,
        grid: BeatGrid?,
        anchors: [Double],
        threshold: Double,
        isEnabled: Bool = true,
    ) -> Snap {
        guard isEnabled, let target = nearest(to: time, grid: grid, anchors: anchors, threshold: threshold)
        else { return Snap(time: time) }
        return Snap(time: target, guide: target)
    }

    /// Snaps a whole clip by whichever of its two edges is closer to a target.
    ///
    /// Both ends are tested because both are things people line up: a clip
    /// starts on the kick, and it also ends where the next one begins. The
    /// length never changes — moving is not resizing.
    ///
    /// - Returns: the clip's new start, and the time the winning edge caught.
    public static func move(
        start: Double,
        length: Double,
        grid: BeatGrid?,
        anchors: [Double],
        threshold: Double,
        isEnabled: Bool = true,
    ) -> Snap {
        guard isEnabled else { return Snap(time: start) }

        let end = start + length
        let byStart = nearest(to: start, grid: grid, anchors: anchors, threshold: threshold)
        let byEnd = nearest(to: end, grid: grid, anchors: anchors, threshold: threshold)

        switch (byStart, byEnd) {
        case let (s?, e?):
            return abs(s - start) <= abs(e - end)
                ? Snap(time: s, guide: s)
                : Snap(time: e - length, guide: e)
        case let (s?, nil):
            return Snap(time: s, guide: s)
        case let (nil, e?):
            return Snap(time: e - length, guide: e)
        case (nil, nil):
            return Snap(time: start)
        }
    }

    /// The closest target within reach, beat or anchor.
    ///
    /// Only the beat line nearest `time` is asked for rather than every line in
    /// reach: the grid already answers that in one step, and `lines(in:)` would
    /// walk a range on every pointer event.
    private static func nearest(
        to time: Double,
        grid: BeatGrid?,
        anchors: [Double],
        threshold: Double,
    ) -> Double? {
        var best: Double?
        var bestDistance = threshold

        func consider(_ candidate: Double) {
            let distance = abs(candidate - time)
            if distance <= bestDistance {
                best = candidate
                bestDistance = distance
            }
        }

        if let grid, !grid.isEmpty { consider(grid.snap(time)) }
        // After the beat, and with `<=`: an anchor sitting exactly on a beat is
        // the same line, and an anchor tied with one is the more specific
        // answer — that clip is what the hand is lining up with.
        for anchor in anchors { consider(anchor) }

        return best
    }
}
