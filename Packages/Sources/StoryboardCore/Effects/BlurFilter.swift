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

            // The ends of the range stand in beyond it, or the stack shows
            // nothing wherever the radius sits past the outermost level.
            //
            // Strictly past, not `<=`/`>=`: a level is trivially equal to
            // itself, so the loose test held the top level opaque at *every*
            // instant and a radius running 20 → 0 → 20 stayed blurred from end
            // to end.
            func clampedWeight(at time: Double) -> Double {
                let actual = context.number(Param.radius, at: time)
                if level == levels.first, actual < Double(level) { return 1 }
                if level == levels.last, actual > Double(level) { return 1 }
                return Self.weight(forLevel: level, atRadius: actual, step: step)
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

        // Enough samples that a cut lands within a fraction of a pixel of each
        // corner in the weight curve.
        //
        // The curve is piecewise linear with corners where the radius is half a
        // step and a full step away — and a command interpolates *between* its
        // cuts, so a cut landing near a corner rather than on it rounds the
        // corner off. Measured on a 0→20 ramp: a level that should have been
        // flat at 1.000 read 0.996 and drifting, and the pair composited to
        // 0.968 instead of 1. Small, and visible as flicker because it repeats
        // at every one of the eleven crossings.
        let samples = 2000
        let interval = (last - first) / Double(samples)

        // Every sample where this level's weight **changes**, rather than where
        // it enters and leaves its band.
        //
        // Edge detection assumed a level starts outside its band. One that
        // begins inside — a radius running 20 → 0 → 20 starts sitting on the
        // top level — recorded no boundary at all and came out as a single
        // command held opaque for the whole clip, so the picture stayed blurred
        // from end to end.
        //
        // Asking "did the weight move" needs no such assumption, and it catches
        // each pass's peak for free: the weight stops changing there.
        var times: [Double] = []
        var previous: Double?

        for index in 0 ... samples {
            let time = first + interval * Double(index)
            let value = Self.weight(
                forLevel: level, atRadius: radius(time), step: step,
            )
            if let previous, abs(value - previous) > 0.001 {
                // **Two** cuts, a moment apart.
                //
                // The weight is a step function now — one level at a time — and
                // a command interpolates between its cuts, so a single cut
                // turns the step into a ramp: measured, levels reading 0.33 and
                // 0.20 that the rule says are zero, and the pair of them
                // showing at once is the halo that pulses. A pair of cuts a
                // millisecond apart leaves the switch as a switch.
                times.append(max(first, time - 1))
                times.append(time)
            }
            previous = value
        }
        return times
    }

    /// How opaque one level is at a given radius.
    ///
    /// The single rule both the cuts and the gate read. Two places computing it
    /// separately is how they come to disagree — and a cut placed where the
    /// weight does *not* change is a command written for nothing.
    static func weight(forLevel level: Int, atRadius radius: Double, step: Double) -> Double {
        // **One level at a time.** The nearest, at full opacity; every other at
        // nothing.
        //
        // Cross-fading neighbours is the obvious answer and it is what caused
        // the flicker, for a reason no amount of weighting could fix: a blurred
        // image is *physically larger* than the one it came from — the blur is
        // drawn on a canvas grown by `radius × 3` so the light is not clipped —
        // so two levels superimposed do not cover each other. The wider one
        // shows all the way around the narrower, and as its opacity rises and
        // falls across a crossing that halo **pulses**.
        //
        // Measured, the two levels summed to 2.02 where an `over` composite of
        // identical shapes would give 1.0: the extra light is exactly the ring
        // spilling past the edge.
        //
        // Switching levels outright means a visible step at each boundary
        // rather than a smooth ramp — but the step between two adjacent blur
        // radii is two pixels of softness, which is far less noticeable than a
        // halo breathing around the subject.
        abs(radius - Double(level)) <= step / 2 ? 1 : 0
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
