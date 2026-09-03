import Foundation

/// Pulls a dragged clip onto the stage's own landmarks.
///
/// Placing something at the centre by eye is a thing nobody can do: a clip
/// lands at 319 or 322 and looks centred until it sits beside something that
/// really is. Snapping makes the obvious positions reachable, which is most of
/// what precise placement means in practice.
///
/// The landmarks are the stage's own — centre, edges, thirds — rather than
/// other clips. Those need every visible clip measured on every frame of a
/// drag; these need nothing but the stage, and they are the ones anyone reaches
/// for first.
public enum StageSnap {
    /// Stage dimensions in storyboard coordinates.
    ///
    /// Spelled out here because `StoryboardCore` sits below the renderer and
    /// cannot import `OsuCanvas`. A test checks the two agree — a silent
    /// disagreement would snap clips to a centre that is not the centre.
    public enum Stage {
        public static let width: Double = 854
        public static let height: Double = 480
        /// The wide stage starts left of the frame: it is the 4:3 playfield
        /// with a margin either side.
        public static let minX: Double = -107
        public static let maxX: Double = 747
        public static let minY: Double = 0
        public static let maxY: Double = 480
        public static let centreX: Double = 320
        public static let centreY: Double = 240
    }

    /// How close a clip has to be, in stage units, before it snaps.
    ///
    /// Measured in stage units rather than points so the pull feels the same at
    /// any zoom: a threshold in points would snap from a mile away when zoomed
    /// out and be unreachable when zoomed in.
    public static let threshold: Double = 6

    /// What a clip snapped to, so the canvas can draw the line it landed on.
    public struct Result: Sendable, Equatable {
        public var dx: Double
        public var dy: Double
        /// The x landmark it caught, if any.
        public var snappedX: Double?
        /// The y landmark it caught, if any.
        public var snappedY: Double?

        public init(dx: Double, dy: Double, snappedX: Double? = nil, snappedY: Double? = nil) {
            self.dx = dx
            self.dy = dy
            self.snappedX = snappedX
            self.snappedY = snappedY
        }
    }

    /// The vertical lines a clip can catch.
    public static let verticalLines: [Double] = [
        Stage.minX,
        Stage.minX + Stage.width / 3,
        Stage.centreX,
        Stage.maxX - Stage.width / 3,
        Stage.maxX,
    ]

    /// The horizontal lines a clip can catch.
    public static let horizontalLines: [Double] = [
        Stage.minY,
        Stage.height / 3,
        Stage.centreY,
        Stage.height * 2 / 3,
        Stage.maxY,
    ]

    /// Adjusts a drag so the clip lands on a landmark when it is close enough.
    ///
    /// Three points per axis are tested — the clip's leading edge, its centre
    /// and its trailing edge — because all three are things people line up.
    /// A box is centred on the stage, but it is also pushed flush against an
    /// edge, and a letterbox bar is both at once.
    ///
    /// - Parameters:
    ///   - box: where the clip is before the drag.
    ///   - drag: how far the hand has moved, in stage units.
    ///   - isEnabled: passing `false` returns the drag untouched, so the caller
    ///     can offer the usual "hold to disable" without a second path.
    public static func adjust(
        _ box: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        by drag: (dx: Double, dy: Double),
        isEnabled: Bool = true,
    ) -> Result {
        guard isEnabled else { return Result(dx: drag.dx, dy: drag.dy) }

        let x = nearest(
            edges: [box.minX + drag.dx, (box.minX + box.maxX) / 2 + drag.dx, box.maxX + drag.dx],
            to: verticalLines,
        )
        let y = nearest(
            edges: [box.minY + drag.dy, (box.minY + box.maxY) / 2 + drag.dy, box.maxY + drag.dy],
            to: horizontalLines,
        )

        return Result(
            dx: drag.dx + (x?.correction ?? 0),
            dy: drag.dy + (y?.correction ?? 0),
            snappedX: x?.line,
            snappedY: y?.line,
        )
    }

    // ─── Aligning ────────────────────────────────────────────────────────────

    /// Where a clip can be sent on the stage.
    ///
    /// The same landmarks a drag snaps to, reached by asking rather than by
    /// aiming. Snapping helps once a hand is already close; this is for "put it
    /// in the middle", which is a thing to state rather than to approximate.
    public enum Alignment: String, CaseIterable, Sendable {
        case left = "Left"
        case centreHorizontally = "Centre"
        case right = "Right"
        case top = "Top"
        case middle = "Middle"
        case bottom = "Bottom"

        public var isHorizontal: Bool {
            switch self {
            case .left, .centreHorizontally, .right: true
            case .top, .middle, .bottom: false
            }
        }

        public var systemImage: String {
            switch self {
            case .left: "align.horizontal.left"
            case .centreHorizontally: "align.horizontal.center"
            case .right: "align.horizontal.right"
            case .top: "align.vertical.top"
            case .middle: "align.vertical.center"
            case .bottom: "align.vertical.bottom"
            }
        }
    }

    /// How far to move a clip so it lands on a stage landmark.
    ///
    /// Returned as a nudge rather than a position, because a clip's transform
    /// holds where its *pivot* is and the box measures where its pixels are —
    /// which for anything but a centred sprite are two different numbers. A
    /// caller adds this to whatever the clip's position already is.
    public static func offset(
        toAlign box: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        _ alignment: Alignment,
    ) -> (dx: Double, dy: Double) {
        switch alignment {
        case .left:
            (dx: Stage.minX - box.minX, dy: 0)
        case .centreHorizontally:
            (dx: Stage.centreX - (box.minX + box.maxX) / 2, dy: 0)
        case .right:
            (dx: Stage.maxX - box.maxX, dy: 0)
        case .top:
            (dx: 0, dy: Stage.minY - box.minY)
        case .middle:
            (dx: 0, dy: Stage.centreY - (box.minY + box.maxY) / 2)
        case .bottom:
            (dx: 0, dy: Stage.maxY - box.maxY)
        }
    }

    /// The closest landmark any of the clip's edges is near, and how far to
    /// nudge it.
    ///
    /// The nearest of all of them rather than the first found: a small clip can
    /// sit within reach of two lines at once, and the closer one is the one a
    /// hand is aiming at.
    private static func nearest(
        edges: [Double],
        to lines: [Double],
    ) -> (line: Double, correction: Double)? {
        var best: (line: Double, correction: Double)?
        var bestDistance = threshold

        for edge in edges {
            for line in lines {
                let distance = abs(line - edge)
                guard distance < bestDistance else { continue }
                bestDistance = distance
                best = (line, line - edge)
            }
        }

        return best
    }
}
