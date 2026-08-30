import Foundation

/// Softens whatever is on the track.
///
/// Unlike ``GlowFilter``, this adds nothing: it swaps each sprite's image for a
/// blurred version of itself. One sprite in, one sprite out — the only filter
/// here that costs nothing at all in file size, because softness lives in the
/// pixels rather than in extra copies.
///
/// A blur in a compositor is a screen-space pass over whatever is behind it.
/// This is not that, and cannot be: it softens each sprite on its own, so
/// overlapping sprites stay distinct where a real blur would smear them
/// together. For a particle field — which is what most of this is — the
/// difference does not read.
public struct BlurFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let radius = "radius"
        public static let opacity = "opacity"
    }

    public static let descriptor = FilterDescriptor(
        type: "blur",
        name: "Blur",
        category: "Stylise",
        systemImage: "drop.halffull",
        parameters: [
            EffectParameter(
                id: Param.radius,
                name: "Radius",
                group: "Blur",
                defaultValue: .number(8),
                range: 0...64,
                step: 2,
                unit: "px",
            ),
            // Blurring spreads a sprite's light over a larger area, so the same
            // opacity reads brighter than the original did. This is how to put
            // that back.
            EffectParameter(
                id: Param.opacity,
                name: "Opacity",
                group: "Blur",
                defaultValue: .number(1),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
        ],
    )

    /// Nothing is added, so nothing multiplies.
    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let radius = context.number(Param.radius)
        let opacity = context.number(Param.opacity)

        guard radius > 0 else { return sprites }

        return sprites.map { sprite in
            var blurred = sprite
            blurred.filePath = DerivedSprite.blurred(sprite.filePath, radius: radius)

            guard opacity != 1 else { return blurred }

            blurred.commands = sprite.commands.map { command in
                guard case let .fade(start, end) = command.payload else { return command }
                return Command(
                    timing: command.timing,
                    payload: .fade(start: start * opacity, end: end * opacity),
                )
            }
            return blurred
        }
    }
}
