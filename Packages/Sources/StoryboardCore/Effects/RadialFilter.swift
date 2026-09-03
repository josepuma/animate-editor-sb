import Foundation

/// Copies a clip around a circle.
///
/// The most visible filter per line of code in the library: anything at all
/// becomes a mandala. A single spark repeated eight times is a starburst, a
/// drifting wisp is a flower, and none of it needs a new effect.
///
/// The cost is honest and steep — one copy per arm, on top of the original —
/// so the multiplier says so before the file is written.
public struct RadialFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let count = "count"
        public static let radius = "radius"
        public static let spin = "spin"
        public static let mirror = "mirror"
        public static let arc = "arc"
        public static let twist = "twist"
    }

    public static let descriptor = FilterDescriptor(
        type: "radial",
        name: "Radial Repeat",
        category: .stylise,
        systemImage: "circle.hexagongrid",
        parameters: [
            EffectParameter(
                id: Param.count,
                name: "Arms",
                group: "Radial",
                defaultValue: .integer(6),
                range: 2...16,
                step: 1,
            ),
            // Pushing the copies off the centre before turning them: without
            // it a clip already at the middle just rotates in place, which is
            // a spin rather than a pattern.
            EffectParameter(
                id: Param.radius,
                name: "Offset",
                group: "Radial",
                defaultValue: .number(0),
                range: 0...300,
                step: 5,
                unit: "px",
            ),
            // How much of the circle the arms fill.
            //
            // A full turn always reads as a mandala, however it is tuned —
            // it is the shape of the thing. Narrowed, the same filter makes
            // fans, wings and directional splashes, which is a different family
            // of effect from the same handful of parameters.
            EffectParameter(
                id: Param.arc,
                name: "Spread",
                group: "Radial",
                defaultValue: .number(360),
                range: 15...360,
                step: 5,
                unit: "°",
            ),
            // Each arm turned a little further than the one before it.
            //
            // The difference between a star and a spiral: with every arm at the
            // same angle the figure is rigid, and a rising offset winds it into
            // a galaxy. Zero by default, which is the plain repeat.
            EffectParameter(
                id: Param.twist,
                name: "Twist",
                group: "Radial",
                defaultValue: .number(0),
                range: -180...180,
                step: 5,
                unit: "°",
            ),
            // Whether each copy turns to face outward.
            //
            // On by default because it is what makes a pattern: arms that all
            // point the same way read as a scatter of the same thing, while
            // arms that follow the circle read as one figure.
            EffectParameter(
                id: Param.spin,
                name: "Face Outward",
                group: "Radial",
                defaultValue: .toggle(true),
            ),
            EffectParameter(
                id: Param.mirror,
                name: "Mirror Alternate",
                group: "Radial",
                defaultValue: .toggle(false),
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        Double(max(2, context.integer(Param.count)))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let arms = max(2, context.integer(Param.count))
        let radius = context.number(Param.radius)
        let arc = context.number(Param.arc)
        let twist = context.number(Param.twist)
        let facesOutward = context.toggle(Param.spin)
        let mirrors = context.toggle(Param.mirror)

        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue

        var result: [StoryboardSprite] = []
        result.reserveCapacity(sprites.count * arms)

        for arm in 0 ..< arms {
            // A full circle wraps, so the last arm would land on the first —
            // divided by the count it never does. A partial arc does not wrap,
            // so its ends are two distinct positions and the arms divide the
            // gaps *between* them: a 90° fan of four wants arms at 0, 30, 60
            // and 90, not at 0, 22.5, 45 and 67.5 with nothing at the edge.
            let sweep = arc * .pi / 180
            let steps = arc >= 359.9 ? Double(arms) : Double(max(1, arms - 1))
            let placement = sweep * Double(arm) / steps

            // Twist accumulates: each arm is turned a little further than the
            // one before, which is what winds the figure into a spiral rather
            // than rotating it as a whole.
            let angle = placement + twist * .pi / 180 * Double(arm) / Double(arms)
            // Mirrored arms turn the other way, which is what makes a
            // reflection rather than a rotation — the difference between a
            // pinwheel and a snowflake.
            let flip = mirrors && arm.isMultiple(of: 2) ? -1.0 : 1.0

            for (index, sprite) in sprites.enumerated() {
                guard arm > 0 || radius > 0 else {
                    result.append(sprite)
                    continue
                }

                var copy = sprite
                if arm > 0 { copy.id = "\(context.idPrefix)/r\(arm)-\(index)" }

                copy.defaultX = centreX
                copy.defaultY = centreY
                copy.commands = sprite.commands.map { command in
                    var turned = command
                    turned.payload = rotate(
                        command.payload,
                        by: angle * flip,
                        radius: radius,
                        centreX: centreX, centreY: centreY,
                        facesOutward: facesOutward,
                    )
                    return turned
                }
                result.append(copy)
            }
        }

        return result
    }

    /// Turns a command's coordinates about the stage centre.
    private func rotate(
        _ payload: Command.Payload,
        by angle: Double,
        radius: Double,
        centreX: Double,
        centreY: Double,
        facesOutward: Bool,
    ) -> Command.Payload {
        func turn(_ x: Double, _ y: Double) -> (Double, Double) {
            // Offset first, then rotate: pushing outward after the turn would
            // move every arm the same way and collapse the ring into a smear.
            let dx = x - centreX + radius
            let dy = y - centreY
            return (
                centreX + dx * cos(angle) - dy * sin(angle),
                centreY + dx * sin(angle) + dy * cos(angle)
            )
        }

        switch payload {
        case let .move(startX, startY, endX, endY):
            let from = turn(startX, startY)
            let to = turn(endX, endY)
            return .move(startX: from.0, startY: from.1, endX: to.0, endY: to.1)

        // A single-axis move stops being single-axis once it is turned, so it
        // has to become a full `_M` — kept as `_MX` the arm would slide along
        // the screen instead of along its own spoke.
        case let .moveX(start, end):
            let from = turn(start, centreY)
            let to = turn(end, centreY)
            return .move(startX: from.0, startY: from.1, endX: to.0, endY: to.1)

        case let .moveY(start, end):
            let from = turn(centreX, start)
            let to = turn(centreX, end)
            return .move(startX: from.0, startY: from.1, endX: to.0, endY: to.1)

        case let .rotate(start, end) where facesOutward:
            return .rotate(start: start + angle, end: end + angle)

        default:
            return payload
        }
    }
}
