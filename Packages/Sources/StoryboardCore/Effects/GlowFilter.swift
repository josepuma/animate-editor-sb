import Foundation

/// A halo around whatever is on the track.
///
/// osu! has no shaders, so a glow cannot be a screen-space bloom. What it can
/// be is a second sprite behind the first, drawn additively — and if that
/// sprite is a *blurred copy* of the original, the falloff is a real one rather
/// than an approximation.
///
/// That is the whole design. The earlier version stacked several scaled copies
/// at falling opacity, which works and costs a sprite per layer: three layers
/// over two hundred particles is six hundred sprites. One blurred sprite is a
/// third of that, and it looks better — stacked copies always band where a
/// Gaussian falls off smoothly.
///
/// The halo goes *before* the sprites it belongs to, so the original stays
/// crisp on top. Drawn after, it washes over its own subject and reads as fog.
public struct GlowFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let radius = "radius"
        public static let size = "size"
        public static let intensity = "intensity"
        public static let color = "color"
        public static let tinted = "tinted"
    }

    public static let descriptor = FilterDescriptor(
        type: "glow",
        name: "Glow",
        category: .stylise,
        systemImage: "sun.max",
        parameters: [
            EffectParameter(
                id: Param.radius,
                name: "Softness",
                group: "Glow",
                defaultValue: .number(12),
                range: 0...64,
                step: 2,
                unit: "px",
            ),
            EffectParameter(
                id: Param.size,
                name: "Size",
                group: "Glow",
                // The subject's own size by default: the softness alone is
                // what reads as a glow, and a copy grown before it is blurred
                // is a second, fatter version of the sprite showing past its
                // edges.
                defaultValue: .number(1),
                range: 1...6,
                step: 0.1,
                unit: "×",
                animation: .commands,
            ),
            EffectParameter(
                id: Param.intensity,
                name: "Intensity",
                group: "Glow",
                defaultValue: .number(0.8),
                range: 0...2,
                step: 0.05,
                presentation: .slider,
                // Free to animate: it scales the fade commands the halo was
                // writing anyway. Softness is not here — that lands in a
                // texture path, and one image per value is a different cost
                // entirely.
                animation: .commands,
            ),
            EffectParameter(
                id: Param.tinted,
                name: "Tint Halo",
                group: "Glow",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.color,
                name: "Halo Colour",
                group: "Glow",
                defaultValue: .color(EffectColor(r: 255, g: 220, b: 160)),
            ),
        ],
    )

    /// One halo per sprite, whatever the settings — the point of the blurred
    /// approach is that softness costs pixels rather than sprites.
    public func estimatedMultiplier(in context: FilterContext) -> Double {
        // An animated intensity resting at zero still draws a halo wherever its
        // keys take it, so the estimate has to answer for the whole track and
        // not for one instant of it.
        let draws = context.isAnimated(Param.intensity)
            || context.number(Param.intensity) > 0
        return draws ? 2 : 1
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let radius = context.number(Param.radius)
        let tinted = context.toggle(Param.tinted)
        let haloColour = context.color(Param.color)

        // Where the animated factors change, so a command spanning a keyframe
        // is cut there rather than holding one value across it.
        let cuts = context.keyTimes(of: [Param.size, Param.intensity])
        let size = { context.number(Param.size, at: $0) }
        let intensity = { context.number(Param.intensity, at: $0) }

        // An intensity animated up from zero still has a halo to show later, so
        // only a resting zero with no animation means there is nothing to draw.
        guard context.isAnimated(Param.intensity) || context.number(Param.intensity) > 0
        else { return sprites }

        let halos = sprites.enumerated().map { index, sprite in
            haloCopy(
                of: sprite,
                id: "\(context.idPrefix)/g\(index)",
                radius: radius,
                cuts: cuts,
                scale: size,
                opacity: intensity,
                tint: tinted ? haloColour : nil,
            )
        }

        // Halo first: the originals stay crisp on top of their own light.
        return halos + sprites
    }

    /// A blurred, enlarged, additive copy of a sprite.
    private func haloCopy(
        of sprite: StoryboardSprite,
        id: String,
        radius: Double,
        cuts: [Double],
        scale: @escaping (Double) -> Double,
        opacity: @escaping (Double) -> Double,
        tint: EffectColor?,
    ) -> StoryboardSprite {
        var copy = sprite
        copy.id = id
        // The image the halo draws: the sprite's own, softened. A radius of
        // zero leaves the path alone, so the filter still works as a plain
        // enlarged additive copy for anyone who wants hard edges.
        copy.filePath = radius > 0
            ? DerivedSprite.blurred(sprite.filePath, radius: radius)
            : sprite.filePath

        // Each factor read at both ends of every command, and every command a
        // keyframe falls inside cut there first. Sampled once instead, the halo
        // would freeze at whatever the factor was when the sprite was born
        // while the inspector showed the number moving — the mistake this
        // project has already made with opacity and with scale.
        copy.commands = AnimatedFactor.apply(to: sprite.commands, cutAt: cuts) { command in
            let atStart = command.startTime
            let atEnd = command.endTime

            switch command.payload {
            case let .fade(start, end):
                // Multiplied rather than replaced, so the halo keeps the
                // sprite's own timing — it appears and leaves with its subject
                // instead of hanging in the frame on its own schedule. Clamped,
                // since intensity can exceed one and opacity cannot.
                return Command(
                    timing: command.timing,
                    payload: .fade(
                        start: min(1, start * opacity(atStart)),
                        end: min(1, end * opacity(atEnd)),
                    ),
                )

            case let .scale(start, end):
                return Command(
                    timing: command.timing,
                    payload: .scale(start: start * scale(atStart), end: end * scale(atEnd)),
                )

            case let .vectorScale(startX, startY, endX, endY):
                return Command(
                    timing: command.timing,
                    payload: .vectorScale(
                        startX: startX * scale(atStart), startY: startY * scale(atStart),
                        endX: endX * scale(atEnd), endY: endY * scale(atEnd),
                    ),
                )

            case .color:
                // A tinted halo takes its own colour; an untinted one keeps the
                // sprite's, so a red particle glows red without being told to.
                return tint.map { colour in
                    Command(
                        timing: command.timing,
                        payload: .color(
                            startR: colour.r, startG: colour.g, startB: colour.b,
                            endR: colour.r, endG: colour.g, endB: colour.b,
                        ),
                    )
                } ?? command

            case .parameter(.additive):
                // Already additive; the copy will be too, so drop the duplicate
                // rather than writing it twice.
                return nil

            default:
                return command
            }
        }

        // A sprite with no scale command has an implied scale of 1, and the
        // halo needs to be larger than that.
        if !sprite.commands.contains(where: { $0.kind == .scale || $0.kind == .vectorScale }),
           let first = sprite.commands.map(\.startTime).min()
        {
            // An animated size needs a command that travels, not a value held:
            // the sprite has no scale command of its own for the factor to ride
            // on, so this is the only place the animation can live.
            //
            // And one command per keyframe segment, not one from end to end —
            // a single span would stretch the whole change over the sprite's
            // life and throw away every key in between. The same mistake an
            // animated rotation already made once.
            let last = sprite.commands.map(\.endTime).max() ?? first
            let inside = cuts.filter { $0 > first && $0 < last }

            if inside.isEmpty {
                copy.commands.append(Command(
                    easing: .linear,
                    startTime: first,
                    endTime: first,
                    payload: .scale(start: scale(first), end: scale(first)),
                ))
            } else {
                let bounds = [first] + inside + [last]
                for (from, to) in zip(bounds, bounds.dropFirst()) {
                    copy.commands.append(Command(
                        easing: .linear,
                        startTime: from,
                        endTime: to,
                        payload: .scale(start: scale(from), end: scale(to)),
                    ))
                }
            }
        }

        // Light adds; it does not occlude. Without this the halo is a grey
        // wash sitting behind the sprite rather than a glow around it.
        if let first = sprite.commands.map(\.startTime).min(),
           let last = sprite.commands.map(\.endTime).max()
        {
            copy.commands.append(Command(
                easing: .linear,
                startTime: first,
                endTime: last,
                payload: .parameter(.additive),
            ))
        }

        if let tint, !sprite.commands.contains(where: { $0.kind == .color }) {
            let first = sprite.commands.map(\.startTime).min() ?? 0
            copy.commands.append(Command(
                easing: .linear,
                startTime: first,
                endTime: first,
                payload: .color(
                    startR: tint.r, startG: tint.g, startB: tint.b,
                    endR: tint.r, endG: tint.g, endB: tint.b,
                ),
            ))
        }

        return copy
    }
}

/// Trailing copies of everything on the track, offset in time.
///
/// The motion-blur substitute: a storyboard cannot smear a moving sprite, but
/// it can draw where that sprite *was* a moment ago, fading. Enough copies and
/// the eye reads a trail.
public struct EchoFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let count = "count"
        public static let delay = "delay"
        public static let falloff = "falloff"
        public static let shrink = "shrink"
        public static let tint = "tint"
    }

    public static let descriptor = FilterDescriptor(
        type: "echo",
        name: "Echo",
        category: .stylise,
        systemImage: "wind",
        parameters: [
            EffectParameter(
                id: Param.count,
                name: "Echoes",
                group: "Echo",
                defaultValue: .integer(4),
                range: 1...12,
                step: 1,
            ),
            EffectParameter(
                id: Param.delay,
                name: "Delay",
                group: "Echo",
                defaultValue: .number(60),
                range: 10...1000,
                step: 10,
                unit: "ms",
            ),
            EffectParameter(
                id: Param.falloff,
                name: "Falloff",
                group: "Echo",
                defaultValue: .number(0.6),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            // Zero by default, which is the plain echo: copies at full size,
            // only dimmer. Turned up, the same filter is a trail.
            //
            // Parameters rather than a second filter: an echo and a trail are
            // one idea — copies of where something was — with the trail adding
            // decay. Two entries doing almost the same thing would make someone
            // pick between them without knowing the difference, and whoever
            // wants a streak looks under "Echo" anyway.
            EffectParameter(
                id: Param.shrink,
                name: "Shrink",
                group: "Trail",
                defaultValue: .number(0),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            // Off by default: an echo is the subject's own colour, seen again.
            // A trail is often something else — heat, speed, magic — and that
            // reads as a colour the subject never had.
            EffectParameter(
                id: Param.tint,
                name: "Trail Colour",
                group: "Trail",
                defaultValue: .color(EffectColor(r: 255, g: 255, b: 255)),
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        Double(1 + max(1, context.integer(Param.count)))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let count = max(1, context.integer(Param.count))
        // Nothing to trail from when the subject holds still.
        //
        // An echo shows where something *was*, so a sprite that never moves
        // stacks its copies exactly on top of itself — five sprites, one
        // silhouette, and a file that got bigger for nothing. Text is the usual
        // way to meet this: placed plain it does not travel, so an echo on it
        // looks broken until the clip is given somewhere to go.
        let delay = context.number(Param.delay)
        let falloff = context.number(Param.falloff)
        let shrink = context.number(Param.shrink)
        let tint = context.color(Param.tint)

        guard delay > 0 else { return sprites }

        var trail: [StoryboardSprite] = []
        trail.reserveCapacity(sprites.count * count)

        // Furthest echo first, so the trail is drawn back to front and the
        // newest copy sits nearest the sprite it follows.
        for echo in stride(from: count, through: 1, by: -1) {
            let opacity = pow(1 - falloff, Double(echo) / Double(count))
            let offset = -delay * Double(echo)

            // How far along the trail this copy sits: 0 nearest the subject,
            // 1 at the far end. Older copies are smaller, which is what turns
            // a row of echoes into a streak that recedes.
            let age = Double(echo) / Double(count)
            let scale = 1 - shrink * age
            // White leaves the sprite's own colour alone, so the plain echo is
            // unchanged and a trail colour is something asked for.
            let tinted = tint.r < 255 || tint.g < 255 || tint.b < 255

            for (index, sprite) in sprites.enumerated() {
                var copy = sprite
                copy.id = "\(context.idPrefix)/e\(echo)-\(index)"
                copy.commands = sprite.commands.map { command in
                    var shifted = command
                    shifted.timing.startTime += offset
                    shifted.timing.endTime += offset

                    switch command.payload {
                    case let .fade(start, end):
                        shifted.payload = .fade(start: start * opacity, end: end * opacity)

                    case let .scale(start, end) where scale != 1:
                        shifted.payload = .scale(start: start * scale, end: end * scale)

                    case let .vectorScale(startX, startY, endX, endY) where scale != 1:
                        shifted.payload = .vectorScale(
                            startX: startX * scale, startY: startY * scale,
                            endX: endX * scale, endY: endY * scale,
                        )

                    case let .color(sr, sg, sb, er, eg, eb) where tinted:
                        // Blended towards the trail colour by age, so the
                        // streak drifts out of the subject's own hue rather
                        // than switching to another one at the first copy.
                        func blend(_ own: Double, _ towards: Double) -> Double {
                            own + (towards - own) * age
                        }
                        shifted.payload = .color(
                            startR: blend(sr, tint.r),
                            startG: blend(sg, tint.g),
                            startB: blend(sb, tint.b),
                            endR: blend(er, tint.r),
                            endG: blend(eg, tint.g),
                            endB: blend(eb, tint.b),
                        )

                    default:
                        break
                    }
                    return shifted
                }

                // A sprite with no scale command has an implied scale of 1, and
                // a shrinking copy needs to say it is smaller than that.
                if scale != 1,
                   !sprite.commands.contains(where: { $0.kind == .scale || $0.kind == .vectorScale }),
                   let first = sprite.commands.map(\.startTime).min()
                {
                    copy.commands.append(Command(
                        easing: .linear,
                        startTime: first + offset,
                        endTime: first + offset,
                        payload: .scale(start: scale, end: scale),
                    ))
                }
                copy.loops = sprite.loops.map { loop in
                    var moved = loop
                    moved.startTime += offset
                    return moved
                }
                trail.append(copy)
            }
        }

        return trail + sprites
    }
}
