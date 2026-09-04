import Foundation

/// Adds a restless, seeded wobble to whatever a clip draws.
///
/// After Effects' `wiggle()`, and it earns the same place in a library: nothing
/// else turns something perfectly still into something alive. A title that
/// drifts a pixel or two reads as filmed; the same title nailed to the frame
/// reads as pasted on.
///
/// One sprite in, one sprite out — the wobble is written into the commands, not
/// into extra copies. That makes it the cheapest way to add life there is.
public struct WiggleFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let amount = "amount"
        public static let frequency = "frequency"
        public static let rotation = "rotation"
        public static let scale = "scale"
    }

    public static let descriptor = FilterDescriptor(
        type: "wiggle",
        name: "Wiggle",
        category: .motion,
        systemImage: "wave.3.right",
        parameters: [
            EffectParameter(
                id: Param.amount, name: "Amount", group: "Wiggle",
                defaultValue: .number(6), range: 0...200, step: 1, unit: "px",
                animation: .commands,
            ),
            // Steps per second, not a period: "how often" is the question
            // anyone actually has about a wobble.
            EffectParameter(
                id: Param.frequency, name: "Frequency", group: "Wiggle",
                defaultValue: .number(4), range: 0.2...20, step: 0.2, unit: "/s",
                animation: .commands,
            ),
            EffectParameter(
                id: Param.rotation, name: "Rotation", group: "Wiggle",
                defaultValue: .number(0), range: 0...45, step: 1, unit: "°",
                animation: .commands,
            ),
            EffectParameter(
                id: Param.scale, name: "Scale", group: "Wiggle",
                defaultValue: .number(0), range: 0...1, step: 0.05,
                animation: .commands,
            ),
        ],
    )

    public func apply(
        to sprites: [StoryboardSprite],
        in context: FilterContext,
    ) -> [StoryboardSprite] {
        // Read per step, which this filter can do more cleanly than most: it
        // already writes one command per step, so each simply asks for the
        // amount in force at its own moment. A wobble that grows over a clip is
        // the obvious thing to want and was not expressible before.
        let amount = { context.number(Param.amount, at: $0) }
        let spin = { context.number(Param.rotation, at: $0) }
        let scale = { context.number(Param.scale, at: $0) }

        // A value animated up from nothing still wobbles wherever its keys take
        // it, so resting at zero only means "nothing to do" when nothing is
        // animating it.
        let wobbles = [Param.amount, Param.rotation, Param.scale].contains {
            context.isAnimated($0) || context.number($0) > 0
        }
        guard wobbles else { return sprites }

        // Frequency stays still: it sets how many commands get written, and a
        // count that changes mid-clip is a structure rather than a value.
        let frequency = max(0.2, context.number(Param.frequency))
        let step = 1000 / frequency

        return sprites.enumerated().map { index, sprite in
            // A stream per sprite, so every sprite wobbles differently and
            // raising the count leaves the existing ones alone. Seeded, because
            // a preview that disagrees with the exported file is worse than no
            // wobble at all.
            // Seeded from the filter's own id, which is stable for the life of
            // the node: a wobble that changed on every evaluation would make
            // the preview disagree with the exported file.
            var rng = EffectRandom(seed: Self.seed(from: context.idPrefix)).stream(index)
            return wiggled(sprite, step: step, amount: amount, spin: spin, scale: scale, rng: &rng)
        }
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    // ─── One sprite ──────────────────────────────────────────────────────────

    private func wiggled(
        _ sprite: StoryboardSprite,
        step: Double,
        amount: (Double) -> Double,
        spin: (Double) -> Double,
        scale: (Double) -> Double,
        rng: inout EffectRandom,
    ) -> StoryboardSprite {
        let birth = sprite.commands.map(\.startTime).min() ?? 0
        let death = sprite.commands.map(\.endTime).max() ?? birth
        guard death > birth else { return sprite }

        // Capped, because every step is a command in the file: a long clip at a
        // high frequency would write thousands per sprite. Past this the wobble
        // is faster than anyone can see it anyway.
        let steps = min(Int(((death - birth) / step).rounded(.up)), Self.maximumSteps)
        guard steps > 1 else { return sprite }

        var result = sprite
        var position = (x: 0.0, y: 0.0)
        var moves: [Command] = []

        for index in 0..<steps {
            let start = birth + step * Double(index)
            let end = min(start + step, death)
            guard end > start else { break }

            // Each step travels to a new offset rather than to a fresh random
            // point from the origin: walking from where it is keeps the motion
            // continuous, while sampling independently makes it jump.
            let reach = amount(start)
            let next = (
                x: position.x + rng.symmetric(reach) * 0.6,
                y: position.y + rng.symmetric(reach) * 0.6
            )
            // Pulled back toward centre, or a random walk wanders off and never
            // returns.
            let settled = (x: next.x * 0.7, y: next.y * 0.7)

            if reach > 0 {
                // One movement command per step, replacing whatever was there.
                //
                // osu! has no notion of adding two movements together: two `_M`
                // commands overlapping in time fight over the same property and
                // one of them wins at each instant, which reads as the sprite
                // stuttering between two paths. Reading the subject's position
                // and writing a second command beside it was not enough — the
                // shake has to be folded *into* the movement, so only one
                // command ever describes where the sprite is.
                let from = placement(of: sprite, at: start)
                let to = placement(of: sprite, at: end)

                moves.append(Command(
                    easing: .sineInOut, startTime: start, endTime: end,
                    payload: .move(
                        startX: from.x + position.x,
                        startY: from.y + position.y,
                        endX: to.x + settled.x,
                        endY: to.y + settled.y,
                    ),
                ))
            }
            // Each end read at its own moment, so a wobble that grows keeps
            // growing across the step rather than holding its opening value.
            let spinFrom = spin(start), spinTo = spin(end)
            if spinFrom > 0 || spinTo > 0 {
                result.commands.append(Command(
                    easing: .sineInOut, startTime: start, endTime: end,
                    payload: .rotate(
                        start: rng.symmetric(spinFrom) * .pi / 180,
                        end: rng.symmetric(spinTo) * .pi / 180,
                    ),
                ))
            }
            let scaleFrom = scale(start), scaleTo = scale(end)
            if scaleFrom > 0 || scaleTo > 0 {
                result.commands.append(Command(
                    easing: .sineInOut, startTime: start, endTime: end,
                    payload: .scale(
                        start: 1 + rng.symmetric(scaleFrom),
                        end: 1 + rng.symmetric(scaleTo),
                    ),
                ))
            }

            position = settled
        }

        // The shaken path replaces the original, rather than joining it.
        //
        // The steps already cover the sprite's whole life and carry its own
        // movement inside them — leaving the originals in place would put two
        // descriptions of the same property on top of each other, which is the
        // collision this exists to avoid.
        if !moves.isEmpty {
            result.commands.removeAll {
                $0.kind == .move || $0.kind == .moveX || $0.kind == .moveY
            }
            result.commands += moves
        }

        return result
    }

    /// Where a sprite's own commands put it at a given time.
    ///
    /// A wobble is an offset from wherever the subject is, and the subject may
    /// be moving: read from its resting place instead, the shake becomes an
    /// absolute position that overwrites whatever moved it.
    private func placement(of sprite: StoryboardSprite, at time: Double) -> (x: Double, y: Double) {
        var x = sprite.defaultX
        var y = sprite.defaultY

        for command in sprite.commands {
            guard command.startTime <= time else { continue }
            let span = command.endTime - command.startTime
            let progress = span > 0 ? min(1, (time - command.startTime) / span) : 1

            switch command.payload {
            case let .move(startX, startY, endX, endY):
                x = startX + (endX - startX) * progress
                y = startY + (endY - startY) * progress
            case let .moveX(start, end):
                x = start + (end - start) * progress
            case let .moveY(start, end):
                y = start + (end - start) * progress
            default:
                continue
            }
        }

        return (x, y)
    }

    private static let maximumSteps = 60

    private static func seed(from string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in Array(string.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        return hash
    }
}
