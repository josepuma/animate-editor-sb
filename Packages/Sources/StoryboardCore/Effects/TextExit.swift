import Foundation

/// How a glyph leaves.
///
/// Pure on purpose, like `TextStagger`: values in, commands out, no context.
/// The exit is the part of a text effect that grows axes — named moves, a
/// parametric one, its own order and stagger — and keeping it out of the
/// evaluator keeps `TextEffect` small enough to read.
enum TextExit {
    /// The stream a Random exit order shuffles from, derived from the
    /// effect's own. Its own stream, so choosing an exit order never moves the
    /// entrance's Random shuffle, which draws from the effect's stream itself.
    static let orderTag = 0x0E70
    /// The stream Custom's scatter draws from, derived from each glyph's own —
    /// never the glyph's stream itself, which Explode and Drift draw from.
    static let scatterTag = 0x0E71

    /// The parameters, in the order the inspector shows them.
    static let parameters: [EffectParameter] = {
        typealias P = TextEffect.Param
        let custom = EffectParameter.Condition(parameter: P.exit, isAnyOf: ["Custom"])
        return [
            EffectParameter(
                id: P.fadeOut, name: "Fade Out", group: "Exit",
                defaultValue: .number(0), range: 0...5000, step: 10, unit: "ms",
            ),
            // Leaving is its own move: text that arrives with character and
            // then simply dissolves is half an animation.
            EffectParameter(
                id: P.exit, name: "Exit", group: "Exit",
                defaultValue: .choice("Fade"),
                // Custom and Mirror In last: a saved choice is its name, so
                // the order is free, and the named moves read first.
                options: [
                    "Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift",
                    "Custom", "Mirror In",
                ],
            ),
            // How far Explode and Drift throw. Under any other exit it does
            // nothing, and a control that does nothing lies.
            EffectParameter(
                id: P.exitForce, name: "Exit Force", group: "Exit",
                defaultValue: .number(220), range: 0...1200, step: 10, unit: "px",
                shownWhen: .init(parameter: P.exit, isAnyOf: ["Explode", "Drift"]),
            ),
            // Leaving one after another rather than all at once. Inert at 0
            // whatever the order says; the order has no condition of its own
            // because "shown when the stagger is above zero" is not a choice
            // a condition can name.
            EffectParameter(
                id: P.exitStagger, name: "Exit Stagger", group: "Exit",
                defaultValue: .number(0), range: 0...1000, step: 5, unit: "ms",
            ),
            EffectParameter(
                id: P.exitOrder, name: "Exit Order", group: "Exit",
                defaultValue: .choice("Same"),
                options: ["Same", "Reverse", "Start", "End", "Centre", "Edges", "Random"],
            ),
            // Custom: the exit stated as where each glyph goes, the same axes
            // the entrance states where it comes from. At their defaults they
            // go nowhere, which is the Fade exit.
            EffectParameter(
                id: P.outRise, name: "Rise To", group: "Exit",
                defaultValue: .number(0), range: -400...400, step: 1, unit: "px",
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outDrift, name: "Drift To", group: "Exit",
                defaultValue: .number(0), range: -800...800, step: 1, unit: "px",
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outScale, name: "Scale To", group: "Exit",
                defaultValue: .number(1), range: 0...5, step: 0.05,
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outSpin, name: "Spin To", group: "Exit",
                defaultValue: .number(0), range: -720...720, step: 5, unit: "°",
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outStretchX, name: "Stretch To X", group: "Exit",
                defaultValue: .number(1), range: 0...5, step: 0.05,
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outStretchY, name: "Stretch To Y", group: "Exit",
                defaultValue: .number(1), range: 0...5, step: 0.05,
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outScatter, name: "Scatter Out", group: "Exit",
                defaultValue: .number(0), range: 0...800, step: 5, unit: "px",
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outScatterRotation, name: "Scatter Out Rotation", group: "Exit",
                defaultValue: .number(0), range: 0...360, step: 5, unit: "°",
                shownWhen: custom,
            ),
            EffectParameter(
                id: P.outEasing, name: "Out Easing", group: "Exit",
                defaultValue: .choice("Ease In"),
                options: ["Linear", "Ease In", "Back", "Elastic", "Bounce", "Expo"],
                shownWhen: custom,
            ),
        ]
    }()

    /// The exits that write `parametric` rather than a named move.
    static let parametricNames: Set<String> = ["Custom", "Mirror In"]

    /// Where a parametric exit takes a glyph, relative to where it is.
    struct Target {
        var dx: Double
        var dy: Double
        var scale: Double
        var stretchX: Double
        var stretchY: Double
        /// Degrees, as the inspector states them.
        var spin: Double
        var easing: Easing
    }

    /// The curve a glyph leaves on: each entrance curve's own "in" form.
    ///
    /// One table for the Out Easing control and for Mirror In, which reads the
    /// entrance's: played backwards, an ease out is an ease in, a settle is a
    /// wind-up. Both spellings of the plain ease map to `.in`, so the two
    /// controls can each name it the way it reads.
    static func inEasing(named name: String) -> Easing {
        switch name {
        case "Linear": .linear
        case "Back": .backIn
        case "Elastic": .elasticIn
        case "Bounce": .bounceIn
        case "Expo": .expoIn
        default: .in
        }
    }

    /// How much earlier than the clip's end each glyph leaves, in milliseconds.
    ///
    /// Rank 0 leaves first: the order names who goes first, as it does for the
    /// entrance. Same follows the entrance's own ranks — first in, first out —
    /// and Reverse runs them backwards, so the last to arrive is the first to
    /// go. The others reorder by place in the line, from their own stream.
    /// The latest exit still ends with the clip; the delay moves the others
    /// earlier rather than any of them later.
    static func delays(
        entranceRanks: [Double],
        units: [Int],
        order: String,
        stagger: Double,
        rng: EffectRandom,
    ) -> [Double] {
        guard stagger > 0, let top = entranceRanks.max() else { return entranceRanks.map { _ in 0 } }
        let ranks: [Double]
        switch order {
        case "Same":
            ranks = entranceRanks
        case "Reverse":
            ranks = entranceRanks.map { top - $0 }
        default:
            var stream = rng.stream(orderTag)
            ranks = TextStagger.ranks(units: units, order: order, waveAmount: 0, rng: &stream)
        }
        let last = ranks.max() ?? 0
        return ranks.map { stagger * (last - $0) }
    }

    /// A parametric exit over `[start, end]`, from `from`.
    ///
    /// Only what moves is written: a target at rest on an axis costs nothing on
    /// it, so Custom at its defaults is exactly the Fade exit. `vector` keeps
    /// the scale on `_V` when the sprite already speaks it.
    static func parametric(
        _ target: Target,
        from: (x: Double, y: Double),
        start: Double,
        end: Double,
        vector: Bool,
    ) -> [Command] {
        var commands: [Command] = []
        if target.dx != 0 || target.dy != 0 {
            commands.append(Command(
                easing: target.easing, startTime: start, endTime: end,
                payload: .move(startX: from.x, startY: from.y, endX: from.x + target.dx, endY: from.y + target.dy),
            ))
        }
        if target.scale != 1 || target.stretchX != 1 || target.stretchY != 1 {
            commands.append(Command(
                easing: target.easing, startTime: start, endTime: end,
                payload: vector
                    ? .vectorScale(
                        startX: 1, startY: 1,
                        endX: target.scale * target.stretchX, endY: target.scale * target.stretchY,
                    )
                    : .scale(start: 1, end: target.scale),
            ))
        }
        if target.spin != 0 {
            commands.append(Command(
                easing: target.easing, startTime: start, endTime: end,
                payload: .rotate(start: 0, end: target.spin * .pi / 180),
            ))
        }
        return commands
    }

    /// The named exits phase one shipped, with their arithmetic unchanged.
    ///
    /// Each writes over `[start, end]` from `from` — where the travel left the
    /// glyph — so a glyph never snaps back to its rest place before leaving.
    /// `offset` is the glyph's place relative to the line's centre, which is
    /// what Explode throws outward from. Draws from `rng` only for Explode and
    /// Drift, in the order they always drew: a saved burst keeps its headings.
    static func legacy(
        _ name: String,
        start: Double,
        end: Double,
        from: (x: Double, y: Double),
        offset: (x: Double, y: Double),
        force: Double,
        vector: Bool,
        rng: inout EffectRandom,
    ) -> [Command] {
        switch name {
        case "Rise", "Fall":
            // `_M`, never `_MY`: an axis command overrides `_M` outright and
            // holds its start before its first command, so an entrance that
            // moved never showed and Travel Y snapped back as the glyph left.
            // One sprite never mixes the pair with a single axis.
            let lift: Double = name == "Rise" ? -60 : 60
            return [Command(
                easing: .quadIn, startTime: start, endTime: end,
                payload: .move(startX: from.x, startY: from.y, endX: from.x, endY: from.y + lift),
            )]
        case "Shrink":
            return [Command(
                easing: .quadIn, startTime: start, endTime: end,
                payload: vector
                    ? .vectorScale(startX: 1, startY: 1, endX: 0.2, endY: 0.2)
                    : .scale(start: 1, end: 0.2),
            )]
        case "Grow":
            return [Command(
                easing: .quadIn, startTime: start, endTime: end,
                payload: vector
                    ? .vectorScale(startX: 1, startY: 1, endX: 2, endY: 2)
                    : .scale(start: 1, end: 2),
            )]
        case "Spin":
            return [Command(
                easing: .quadIn, startTime: start, endTime: end,
                payload: .rotate(start: 0, end: .pi),
            )]
        case "Explode", "Drift":
            // Each character leaves on its own heading.
            //
            // A shared direction is a slide, however fast: what reads as an
            // explosion is that no two letters agree on where they are going.
            // Explode throws them outward from the line's centre — which is
            // what a burst does — while Drift picks a heading at random, for
            // smoke rather than shrapnel.
            let angle: Double = if name == "Explode" {
                // Outward from the centre, nudged so a character sitting on the
                // centre line still has somewhere to go.
                atan2(offset.y, offset.x == 0 ? 0.001 : offset.x) + rng.symmetric(0.4)
            } else {
                rng.between(0, .pi * 2)
            }
            let distance = force * rng.between(0.6, 1.4)
            return [
                Command(
                    easing: .quadOut, startTime: start, endTime: end,
                    payload: .move(
                        startX: from.x,
                        startY: from.y,
                        endX: from.x + cos(angle) * distance,
                        endY: from.y + sin(angle) * distance,
                    ),
                ),
                // Tumbling as it goes, each its own way — debris does not spin
                // in unison.
                Command(
                    easing: .linear, startTime: start, endTime: end,
                    payload: .rotate(start: 0, end: rng.symmetric(.pi * 1.5)),
                ),
            ]
        default:
            return []
        }
    }
}
