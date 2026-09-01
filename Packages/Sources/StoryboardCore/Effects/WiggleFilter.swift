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
        category: "Stylise",
        systemImage: "wave.3.right",
        parameters: [
            EffectParameter(
                id: Param.amount, name: "Amount", group: "Wiggle",
                defaultValue: .number(6), range: 0...200, step: 1, unit: "px",
            ),
            // Steps per second, not a period: "how often" is the question
            // anyone actually has about a wobble.
            EffectParameter(
                id: Param.frequency, name: "Frequency", group: "Wiggle",
                defaultValue: .number(4), range: 0.2...20, step: 0.2, unit: "/s",
            ),
            EffectParameter(
                id: Param.rotation, name: "Rotation", group: "Wiggle",
                defaultValue: .number(0), range: 0...45, step: 1, unit: "°",
            ),
            EffectParameter(
                id: Param.scale, name: "Scale", group: "Wiggle",
                defaultValue: .number(0), range: 0...1, step: 0.05,
            ),
        ],
    )

    public func apply(
        to sprites: [StoryboardSprite],
        in context: FilterContext,
    ) -> [StoryboardSprite] {
        let amount = context.number(Param.amount)
        let spin = context.number(Param.rotation)
        let scale = context.number(Param.scale)
        guard amount > 0 || spin > 0 || scale > 0 else { return sprites }

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
        amount: Double,
        spin: Double,
        scale: Double,
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

        for index in 0..<steps {
            let start = birth + step * Double(index)
            let end = min(start + step, death)
            guard end > start else { break }

            // Each step travels to a new offset rather than to a fresh random
            // point from the origin: walking from where it is keeps the motion
            // continuous, while sampling independently makes it jump.
            let next = (
                x: position.x + rng.symmetric(amount) * 0.6,
                y: position.y + rng.symmetric(amount) * 0.6
            )
            // Pulled back toward centre, or a random walk wanders off and never
            // returns.
            let settled = (x: next.x * 0.7, y: next.y * 0.7)

            if amount > 0 {
                result.commands.append(Command(
                    easing: .sineInOut, startTime: start, endTime: end,
                    payload: .move(
                        startX: sprite.defaultX + position.x,
                        startY: sprite.defaultY + position.y,
                        endX: sprite.defaultX + settled.x,
                        endY: sprite.defaultY + settled.y,
                    ),
                ))
            }
            if spin > 0 {
                result.commands.append(Command(
                    easing: .sineInOut, startTime: start, endTime: end,
                    payload: .rotate(
                        start: rng.symmetric(spin) * .pi / 180,
                        end: rng.symmetric(spin) * .pi / 180,
                    ),
                ))
            }
            if scale > 0 {
                result.commands.append(Command(
                    easing: .sineInOut, startTime: start, endTime: end,
                    payload: .scale(
                        start: 1 + rng.symmetric(scale),
                        end: 1 + rng.symmetric(scale),
                    ),
                ))
            }

            position = settled
        }

        return result
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
