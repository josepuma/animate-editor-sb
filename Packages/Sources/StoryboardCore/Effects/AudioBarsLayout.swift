import Foundation

public extension AudioBarsEffect {
    /// Where the bars stand.
    enum Layout: String, CaseIterable, Sendable {
        /// A row, bass on the left — the original, and still the default.
        case line = "Line"
        /// Around a ring, every bar pointing away from the centre: the circular
        /// spectrum every music-channel visual uses.
        case circle = "Circle"
        /// Part of a ring, centred on the top.
        case arc = "Arc"
        /// Along the edges of a regular polygon, the bars on one edge standing
        /// parallel — which is what makes it read as a polygon rather than as a
        /// circle with corners.
        case polygon = "Polygon"
    }

    /// What each band draws.
    enum Element: String, CaseIterable, Sendable {
        /// A bar that grows with its band.
        case bar = "Bar"
        /// A dot riding where the bar's tip would be: it moves instead of
        /// scaling. Many small dots on a centred line are a waveform.
        case dots = "Dots"
        /// A column of segments that lights up to the level, like an LED meter.
        case segments = "Segments"
    }

    /// Where one band stands: its root, relative to the clip's centre, and the
    /// direction it grows, as a screen angle (0 is right, a quarter turn is
    /// DOWN — this is a Y-down space).
    struct Placement: Sendable {
        public var x: Double
        public var y: Double
        public var direction: Double

        /// The sprite rotation that points a sprite drawn "up" along
        /// `direction`.
        ///
        /// Up is (0, −1). The shader turns it with the standard matrix in a
        /// Y-down space, which lands it on (sin r, −cos r); asking that to equal
        /// (cos d, sin d) gives r = d + π/2. Written out because the emitter's
        /// streaks get away with the opposite sign — a streak is symmetric —
        /// and a bar rooted at one end is not.
        public var rotation: Double { direction + .pi / 2 }
    }

    /// Where each of `count` bands stands.
    static func placements(
        _ layout: Layout,
        count: Int,
        spacing: Double,
        radius: Double,
        arcSpan: Double,
        sides: Int,
    ) -> [Placement] {
        let up = -Double.pi / 2
        switch layout {
        case .line:
            // Around the clip's centre, because a transform turns and scales
            // about that point: a bank laid out from one corner would sweep one
            // end round when rotated.
            let left = -spacing * Double(count - 1) / 2
            return (0 ..< count).map { Placement(x: left + spacing * Double($0), y: 0, direction: up) }

        case .circle:
            // From the top, clockwise, the whole way round.
            return (0 ..< count).map { index in
                let angle = up + 2 * .pi * Double(index) / Double(count)
                return Placement(x: cos(angle) * radius, y: sin(angle) * radius, direction: angle)
            }

        case .arc:
            // Centred on the top, both ends included — an arc does not wrap,
            // so its two ends are two different places.
            let span = arcSpan * .pi / 180
            return (0 ..< count).map { index in
                let t = count > 1 ? Double(index) / Double(count - 1) : 0.5
                let angle = up - span / 2 + span * t
                return Placement(x: cos(angle) * radius, y: sin(angle) * radius, direction: angle)
            }

        case .polygon:
            // Evenly along the perimeter, a vertex at the top. Each bar takes
            // the normal of the edge it stands on rather than the line back to
            // the centre, so an edge's bars stand parallel.
            let sides = max(3, sides)
            let vertex = { (k: Int) -> (x: Double, y: Double) in
                let angle = up + 2 * .pi * Double(k) / Double(sides)
                return (cos(angle) * radius, sin(angle) * radius)
            }
            return (0 ..< count).map { index in
                let t = (Double(index) + 0.5) / Double(count) * Double(sides)
                let edge = min(sides - 1, Int(t))
                let along = t - Double(edge)
                let a = vertex(edge), b = vertex(edge + 1)
                let normal = up + 2 * .pi * (Double(edge) + 0.5) / Double(sides)
                return Placement(
                    x: a.x + (b.x - a.x) * along,
                    y: a.y + (b.y - a.y) * along,
                    direction: normal,
                )
            }
        }
    }
}
