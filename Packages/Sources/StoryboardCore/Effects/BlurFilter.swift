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
                Self.covering(sprite.commands, birth: birth, death: death),
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

    /// The sprite's commands, with its opacity guaranteed to span its whole
    /// life.
    ///
    /// The gate works by *multiplying* the fades a sprite already has, so a
    /// stretch with no fade command over it has nothing to turn on — and a
    /// sprite that fades in, holds, and fades out has exactly that shape: two
    /// short commands at the ends and a silent middle where its opacity is
    /// simply whatever the last one left.
    ///
    /// Measured on a text clip: every glyph carried a fade at `0-40` and
    /// another at `6176-6376`, and the entire middle — where the radius
    /// travels — had none. All eleven blur levels came out invisible.
    ///
    /// The hold is written at whatever the sprite's own fade left it at, so a
    /// sprite that was already fully opaque is unchanged.
    private static func covering(
        _ commands: [Command], birth: Double, death: Double,
    ) -> [Command] {
        let fades = commands.filter { $0.kind == .fade }.sorted { $0.startTime < $1.startTime }
        guard !fades.isEmpty else { return commands }

        // Every gap between consecutive fades, not only the tail.
        //
        // A sprite that fades in, holds and fades out leaves its hole in the
        // *middle*: the last command by end time already reaches death, so
        // looking only past it finds nothing. The hole is between the fade-in
        // ending and the fade-out starting, which is exactly where a radius
        // usually travels.
        var filled = commands
        for (earlier, later) in zip(fades, fades.dropFirst()) {
            guard later.startTime > earlier.endTime + 1,
                  case let .fade(_, held) = earlier.payload, held > 0
            else { continue }
            filled.append(Command(
                easing: .linear,
                startTime: earlier.endTime,
                endTime: later.startTime,
                payload: .fade(start: held, end: held),
            ))
        }

        // And the tail, for a sprite whose last fade ends before it does.
        if let last = fades.last, last.endTime < death - 1,
           case let .fade(_, held) = last.payload, held > 0
        {
            filled.append(Command(
                easing: .linear,
                startTime: last.endTime,
                endTime: death,
                payload: .fade(start: held, end: held),
            ))
        }
        return filled
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
        toLevel level: Int,
        of levels: [Int],
        birth: Double,
        death: Double,
        opacity: Double,
        in context: FilterContext,
    ) -> [Command] {
        let radius = { context.number(Param.radius, at: $0) }
        let step = DerivedSprite.quantumStep

        // Cut where the radius crosses **this level's own band**, not only at
        // its keyframes.
        //
        // A keyframe is where the value changes *direction*; a level turns on
        // and off wherever the radius passes it, which is somewhere else
        // entirely. With only keyframe cuts, a run from 0 to 20 across one
        // command gave every intermediate level a single span whose two ends
        // both sit outside its band — so all nine came out at opacity zero and
        // the blur jumped from sharp straight to full. Measured on a text clip:
        // eleven levels, nine of them invisible.
        let cuts = (context.keyTimes(of: [Param.radius]) + crossings(
            of: radius, over: commands, level: level, step: step,
        )).sorted()

        return AnimatedFactor.apply(to: commands, cutAt: cuts) { command in
            guard case let .fade(start, end) = command.payload else { return command }

            func weight(at time: Double) -> Double {
                let actual = context.number(Param.radius, at: time)
                let distance = abs(actual - Double(level))
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
                if level == levels.first, actual <= Double(level) { return 1 }
                if level == levels.last, actual >= Double(level) { return 1 }
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

    /// The moments the radius enters or leaves one level's band.
    ///
    /// Sampled rather than solved, because the radius follows whatever easing
    /// its keyframes carry and there is no closed form for "where does this
    /// curve cross this value". Sampling finely enough is both simpler and
    /// exact enough: a level is a two-pixel band, and a cut a few milliseconds
    /// early or late is invisible against a cross-fade.
    private func crossings(
        of radius: (Double) -> Double,
        over commands: [Command],
        level: Int,
        step: Double,
    ) -> [Double] {
        let starts = commands.map(\.startTime)
        let ends = commands.map(\.endTime)
        guard let first = starts.min(), let last = ends.max(), last > first else { return [] }

        // Enough samples to catch a band crossing without writing a command per
        // sample: the cuts these produce are bounded by how many times the
        // radius can cross one band, not by the sample count.
        let samples = 240
        let interval = (last - first) / Double(samples)

        var times: [Double] = []
        var wasInside = false
        var closest: (time: Double, distance: Double)?

        for index in 0 ... samples {
            let time = first + interval * Double(index)
            let distance = abs(radius(time) - Double(level))
            let inside = distance < step

            if inside != wasInside {
                if index > 0 { times.append(time) }
                // Leaving the band closes off the pass just measured, so its
                // nearest approach is recorded before the next one starts.
                if !inside, let peak = closest { times.append(peak.time) }
                closest = nil
            }
            if inside, closest == nil || distance < closest!.distance {
                closest = (time, distance)
            }
            wasInside = inside
        }
        // A pass still open at the end has its peak recorded too.
        if wasInside, let peak = closest { times.append(peak.time) }

        // The nearest approach as well as the edges.
        //
        // Cutting only where a level's band starts and ends leaves one command
        // spanning the whole pass — and the weight at *both* of its ends is
        // zero, because that is what being on the edge of a band means. The
        // level then fades in to nothing and out again: measured, every
        // intermediate level peaked at 0.08 instead of 1.00, so a blur running
        // 0→20 was very nearly invisible in between.
        return times.sorted()
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
