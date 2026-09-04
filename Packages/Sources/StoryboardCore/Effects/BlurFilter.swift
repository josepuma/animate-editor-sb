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
        category: .stylise,
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
                // The expensive kind of animation, and the only parameter in
                // the library that is. A radius names a texture rather than
                // landing in a command, so each distinct value it passes
                // through is another sprite — see `levels(in:)`.
                animation: .textures(step: DerivedSprite.quantumStep),
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

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let opacity = context.number(Param.opacity)

        guard context.isAnimated(Param.radius) else {
            let radius = context.number(Param.radius)
            guard radius > 0 else { return sprites }
            return sprites.map { softened($0, radius: radius, opacity: opacity) }
        }

        return sprites.enumerated().flatMap { index, sprite in
            levelled(sprite, index: index, opacity: opacity, in: context)
        }
    }

    /// One sprite, its image swapped for a blurred version of itself.
    private func softened(
        _ sprite: StoryboardSprite,
        radius: Double,
        opacity: Double,
    ) -> StoryboardSprite {
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

    /// An animated radius, as one sprite per blur level.
    ///
    /// A radius names a texture, and osu! draws one image for a sprite's whole
    /// life — so a blur that changes cannot be one sprite. It is a stack of
    /// them, each holding a fixed level and each visible only while the radius
    /// is near it.
    ///
    /// ## Why not simply cross-fade sharp against fully blurred
    ///
    /// That is the obvious two-sprite answer and it does not work. Measured on
    /// a hard-edged subject, the steepest luminance step across the middle row:
    /// the sharp original is 255, a 50/50 cross-fade is **129**, and a genuine
    /// half-radius blur is **17**. The cross-fade halves the *contrast* of the
    /// edge while leaving it one pixel wide — and blurring means widening the
    /// edge. It reads as a faded sharp image, not a soft one.
    ///
    /// Between *neighbouring* levels the same trick is fine, because the two
    /// images differ only slightly and the eye reads the mix as an in-between.
    /// So: real blur at every level, cross-fades only across one step.
    private func levelled(
        _ sprite: StoryboardSprite,
        index: Int,
        opacity: Double,
        in context: FilterContext,
    ) -> [StoryboardSprite] {
        let birth = sprite.commands.map(\.startTime).min() ?? 0
        let death = sprite.commands.map(\.endTime).max() ?? birth
        guard death > birth else { return [softened(sprite, radius: 0, opacity: opacity)] }

        // The window of the sprite's own life, in the radius track's terms —
        // a particle born late must show the radius in force *then*, not the
        // one the clip started with.
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map {
            context.number(Param.radius, at: birth + (death - birth) * $0)
        }
        let low = samples.min() ?? 0
        let high = samples.max() ?? 0
        let levels = DerivedSprite.levels(from: low, to: high)

        // One level is a still blur wearing an animation's clothes.
        guard levels.count > 1 else {
            return [softened(sprite, radius: low, opacity: opacity)]
        }

        return levels.enumerated().map { level, radius in
            var copy = sprite
            copy.id = "\(context.idPrefix)/b\(index)l\(level)"
            copy.filePath = radius > 0
                ? DerivedSprite.blurred(sprite.filePath, radius: Double(radius))
                : sprite.filePath
            copy.commands = gated(
                sprite.commands,
                toLevel: radius,
                of: levels,
                birth: birth,
                death: death,
                opacity: opacity,
                in: context,
            )
            return copy
        }
    }

    /// A copy's commands, with its opacity gated to the stretch where its own
    /// blur level is the one in force.
    ///
    /// The gate multiplies whatever fade the sprite already had rather than
    /// replacing it: a particle still has to be born, live and die on its own
    /// schedule, and a level that ignored that would keep drawing after its
    /// subject was gone.
    private func gated(
        _ commands: [Command],
        toLevel radius: Int,
        of levels: [Int],
        birth: Double,
        death: Double,
        opacity: Double,
        in context: FilterContext,
    ) -> [Command] {
        let step = DerivedSprite.quantumStep
        // Cut wherever the radius changes, so a gate can turn within a command
        // the sprite was already drawing.
        let cuts = context.keyTimes(of: [Param.radius])

        return AnimatedFactor.apply(to: commands, cutAt: cuts) { command in
            guard case let .fade(start, end) = command.payload else { return command }

            func weight(at time: Double) -> Double {
                let actual = context.number(Param.radius, at: time)
                let distance = abs(actual - Double(radius))
                guard distance < step else { return 0 }
                // Linear across one step: at the level itself this is 1, at its
                // neighbour 0, and the two always sum to 1 in between — so the
                // pair reads as one image rather than as a dip in brightness
                // halfway across.
                return 1 - distance / step
            }

            // The ends of the range keep their level beyond it, or the stack
            // fades to nothing wherever the radius sits past the outermost
            // sample.
            func clampedWeight(at time: Double) -> Double {
                let actual = context.number(Param.radius, at: time)
                if radius == levels.first, actual <= Double(radius) { return 1 }
                if radius == levels.last, actual >= Double(radius) { return 1 }
                return weight(at: time)
            }

            return Command(
                timing: command.timing,
                payload: .fade(
                    start: start * opacity * clampedWeight(at: command.startTime),
                    end: end * opacity * clampedWeight(at: command.endTime),
                ),
            )
        }
    }

    /// One sprite per blur level the radius passes through.
    ///
    /// The only filter in the library whose cost depends on *how far* a value
    /// travels rather than on a count somebody typed, so the inspector has to
    /// be told before the file is written.
    public func estimatedMultiplier(in context: FilterContext) -> Double {
        guard context.isAnimated(Param.radius),
              let track = context.animations[Param.radius]
        else { return 1 }

        let values = track.keyframes.map(\.value)
        let levels = DerivedSprite.levels(
            from: values.min() ?? 0, to: values.max() ?? 0,
        )
        return Double(levels.count)
    }
}
