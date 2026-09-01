import Foundation

/// A curve across the stage, as a run of points with bézier handles.
///
/// What After Effects draws when a position is animated: the shape a thing
/// travels along, editable as a line rather than as a table of numbers. The
/// distinction that makes it worth having is not the curve itself — keyframes
/// can approximate one — but **what** it moves. A clip's transform carries the
/// finished result, particles and all; a path moves only where the next one is
/// **born**, so what has already been emitted stays where it was and the trail
/// forms behind it.
public struct MotionPath: Sendable, Equatable, Codable {
    /// One point on the curve, with the handles that shape the segments either
    /// side of it.
    ///
    /// Handles are stored relative to the point, so dragging the point moves
    /// its curve with it — absolute handles would leave the shape behind and
    /// snap the curve straight the moment anything moved.
    public struct Point: Sendable, Equatable, Codable {
        public var x: Double
        public var y: Double
        /// Towards the previous point.
        public var inX: Double
        public var inY: Double
        /// Towards the next.
        public var outX: Double
        public var outY: Double

        public init(
            x: Double,
            y: Double,
            inX: Double = 0,
            inY: Double = 0,
            outX: Double = 0,
            outY: Double = 0,
        ) {
            self.x = x
            self.y = y
            self.inX = inX
            self.inY = inY
            self.outX = outX
            self.outY = outY
        }
    }

    public var points: [Point]

    public init(points: [Point] = []) {
        self.points = points
    }

    public var isEmpty: Bool { points.count < 2 }

    /// Where the path is at `t`, from 0 at the first point to 1 at the last.
    ///
    /// Walked by **arc length**, not by segment index. Sampling the segments
    /// evenly is the obvious reading and the wrong one: a short segment and a
    /// long one would take the same time, so anything following the path would
    /// crawl through the tight parts and race down the straights. A path is a
    /// shape, and the speed along it should be the author's to set — not an
    /// accident of where they happened to put the points.
    public func position(at t: Double) -> (x: Double, y: Double)? {
        guard points.count >= 2 else { return points.first.map { ($0.x, $0.y) } }

        let table = lengths()
        let total = table.last ?? 0
        guard total > 0 else { return (points[0].x, points[0].y) }

        let target = min(max(0, t), 1) * total

        // Which segment that distance lands in, and how far along it.
        var segment = 0
        while segment + 1 < table.count, table[segment + 1] < target { segment += 1 }

        let from = table[segment]
        let span = (segment + 1 < table.count ? table[segment + 1] : total) - from
        let local = span > 0 ? (target - from) / span : 0

        return point(onSegment: segment, at: local)
    }

    /// A cubic bézier between two points, using their facing handles.
    private func point(onSegment index: Int, at t: Double) -> (x: Double, y: Double) {
        guard index + 1 < points.count else {
            let last = points[points.count - 1]
            return (last.x, last.y)
        }

        let a = points[index]
        let b = points[index + 1]

        let c1 = (x: a.x + a.outX, y: a.y + a.outY)
        let c2 = (x: b.x + b.inX, y: b.y + b.inY)

        let u = 1 - t
        let w0 = u * u * u
        let w1 = 3 * u * u * t
        let w2 = 3 * u * t * t
        let w3 = t * t * t

        return (
            w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x,
            w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y
        )
    }

    /// Cumulative arc length at each point, approximated by sampling.
    ///
    /// A bézier has no closed-form length, so it is measured rather than
    /// solved: sixteen samples a segment is well past what a viewer can tell
    /// apart on a curve this size, and the whole table is built once per
    /// evaluation rather than per particle.
    private func lengths() -> [Double] {
        var table: [Double] = [0]
        var running = 0.0

        for index in 0 ..< max(0, points.count - 1) {
            var previous = point(onSegment: index, at: 0)
            for step in 1 ... 16 {
                let current = point(onSegment: index, at: Double(step) / 16)
                let dx = current.x - previous.x
                let dy = current.y - previous.y
                running += (dx * dx + dy * dy).squareRoot()
                previous = current
            }
            table.append(running)
        }

        return table
    }

    /// Which way the path is heading at `t`, in degrees.
    ///
    /// For anything that should face where it is going — a rocket, a comet, a
    /// brush that leans into its stroke.
    public func heading(at t: Double) -> Double {
        let step = 0.01
        guard let here = position(at: t),
              let ahead = position(at: min(1, t + step)),
              let behind = position(at: max(0, t - step))
        else { return 0 }

        // Sampled either side, so the direction at the ends is the direction of
        // the curve there rather than of a segment that does not exist.
        let dx = ahead.x - behind.x
        let dy = ahead.y - behind.y
        guard dx != 0 || dy != 0 else { return 0 }

        return atan2(dy, dx) * 180 / .pi
    }
}
