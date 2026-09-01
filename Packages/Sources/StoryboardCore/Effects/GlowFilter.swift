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
        category: "Stylise",
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
                defaultValue: .number(1.6),
                range: 1...6,
                step: 0.1,
                unit: "×",
            ),
            EffectParameter(
                id: Param.intensity,
                name: "Intensity",
                group: "Glow",
                defaultValue: .number(0.8),
                range: 0...2,
                step: 0.05,
                presentation: .slider,
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
        context.number(Param.intensity) > 0 ? 2 : 1
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let radius = context.number(Param.radius)
        let size = context.number(Param.size)
        let intensity = context.number(Param.intensity)
        let tinted = context.toggle(Param.tinted)
        let haloColour = context.color(Param.color)

        guard intensity > 0 else { return sprites }

        let halos = sprites.enumerated().map { index, sprite in
            haloCopy(
                of: sprite,
                id: "\(context.idPrefix)/g\(index)",
                radius: radius,
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
        scale: Double,
        opacity: Double,
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

        copy.commands = sprite.commands.compactMap { command in
            switch command.payload {
            case let .fade(start, end):
                // Multiplied rather than replaced, so the halo keeps the
                // sprite's own timing — it appears and leaves with its subject
                // instead of hanging in the frame on its own schedule. Clamped,
                // since intensity can exceed one and opacity cannot.
                Command(
                    timing: command.timing,
                    payload: .fade(
                        start: min(1, start * opacity),
                        end: min(1, end * opacity),
                    ),
                )

            case let .scale(start, end):
                Command(
                    timing: command.timing,
                    payload: .scale(start: start * scale, end: end * scale),
                )

            case let .vectorScale(startX, startY, endX, endY):
                Command(
                    timing: command.timing,
                    payload: .vectorScale(
                        startX: startX * scale, startY: startY * scale,
                        endX: endX * scale, endY: endY * scale,
                    ),
                )

            case .color:
                // A tinted halo takes its own colour; an untinted one keeps the
                // sprite's, so a red particle glows red without being told to.
                tint.map { colour in
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
                nil

            default:
                command
            }
        }

        // A sprite with no scale command has an implied scale of 1, and the
        // halo needs to be larger than that.
        if !sprite.commands.contains(where: { $0.kind == .scale || $0.kind == .vectorScale }),
           let first = sprite.commands.map(\.startTime).min()
        {
            copy.commands.append(Command(
                easing: .linear,
                startTime: first,
                endTime: first,
                payload: .scale(start: scale, end: scale),
            ))
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
    }

    public static let descriptor = FilterDescriptor(
        type: "echo",
        name: "Echo",
        category: "Stylise",
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

        guard delay > 0 else { return sprites }

        var trail: [StoryboardSprite] = []
        trail.reserveCapacity(sprites.count * count)

        // Furthest echo first, so the trail is drawn back to front and the
        // newest copy sits nearest the sprite it follows.
        for echo in stride(from: count, through: 1, by: -1) {
            let opacity = pow(1 - falloff, Double(echo) / Double(count))
            let offset = -delay * Double(echo)

            for (index, sprite) in sprites.enumerated() {
                var copy = sprite
                copy.id = "\(context.idPrefix)/e\(echo)-\(index)"
                copy.commands = sprite.commands.map { command in
                    var shifted = command
                    shifted.timing.startTime += offset
                    shifted.timing.endTime += offset
                    if case let .fade(start, end) = command.payload {
                        shifted.payload = .fade(start: start * opacity, end: end * opacity)
                    }
                    return shifted
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
