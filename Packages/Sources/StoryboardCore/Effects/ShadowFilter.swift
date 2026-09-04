import Foundation

/// A dark copy behind and offset — what separates something floating over a
/// background from something painted onto it.
///
/// The glow's opposite twin, and near enough its code: both put one copy behind
/// the original. A glow sits centred and adds light; a shadow sits offset and
/// takes it away.
public struct ShadowFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let offsetX = "offsetX"
        public static let offsetY = "offsetY"
        public static let opacity = "opacity"
        public static let softness = "softness"
        public static let colour = "colour"
    }

    public static let descriptor = FilterDescriptor(
        type: "shadow",
        name: "Shadow",
        category: .stylise,
        systemImage: "shadow",
        parameters: [
            EffectParameter(
                id: Param.offsetX, name: "Offset X", group: "Shadow",
                defaultValue: .number(6), range: -200...200, step: 1, unit: "px",
                animation: .commands,
            ),
            EffectParameter(
                id: Param.offsetY, name: "Offset Y", group: "Shadow",
                defaultValue: .number(6), range: -200...200, step: 1, unit: "px",
                animation: .commands,
            ),
            EffectParameter(
                id: Param.opacity, name: "Opacity", group: "Shadow",
                defaultValue: .number(0.5), range: 0...1, step: 0.05,
                animation: .commands,
            ),
            // Softness costs pixels rather than sprites: the copy points at a
            // blurred version of the image instead of being drawn several
            // times. The same bargain the glow already makes.
            EffectParameter(
                id: Param.softness, name: "Softness", group: "Shadow",
                defaultValue: .number(8), range: 0...60, step: 2, unit: "px",
            ),
            EffectParameter(
                id: Param.colour, name: "Colour", group: "Shadow",
                defaultValue: .color(EffectColor(r: 0, g: 0, b: 0)),
            ),
        ],
    )

    public func apply(
        to sprites: [StoryboardSprite],
        in context: FilterContext,
    ) -> [StoryboardSprite] {
        // Read at a moment, so an animated offset or opacity travels with the
        // clip rather than freezing at whatever it was when a sprite was born.
        let cuts = context.keyTimes(of: [Param.offsetX, Param.offsetY, Param.opacity])
        let offsetX = { context.number(Param.offsetX, at: $0) }
        let offsetY = { context.number(Param.offsetY, at: $0) }
        let opacity = { context.number(Param.opacity, at: $0) }
        let softness = context.number(Param.softness)
        let colour = context.color(Param.colour)

        // An animated value resting at nothing still has a shadow to draw
        // wherever its keys take it.
        let moves = context.isAnimated(Param.offsetX) || context.isAnimated(Param.offsetY)
            || context.number(Param.offsetX) != 0 || context.number(Param.offsetY) != 0
        let shows = context.isAnimated(Param.opacity) || context.number(Param.opacity) > 0
        guard shows, moves || softness > 0 else { return sprites }

        var result: [StoryboardSprite] = []
        result.reserveCapacity(sprites.count * 2)

        for sprite in sprites {
            var shadow = sprite
            shadow.id = "\(context.idPrefix)/shadow-\(sprite.id)"
            let birth = sprite.commands.map(\.startTime).min() ?? 0
            shadow.defaultX += offsetX(birth)
            shadow.defaultY += offsetY(birth)

            if softness > 0 {
                shadow.filePath = DerivedSprite.blurred(sprite.filePath, radius: softness)
            }

            // Every coordinate the commands name moves with it, or a sprite
            // that travels leaves its shadow behind at the starting point.
            // An animated offset needs a movement command to displace: a still
            // sprite keeps its position in `defaultX/Y`, read once, so the
            // offset would freeze at its first value.
            let carried = AnimatedFactor.carrying(
                sprite.commands,
                defaultX: sprite.defaultX, defaultY: sprite.defaultY,
                cutAt: (context.isAnimated(Param.offsetX)
                    || context.isAnimated(Param.offsetY)) ? cuts : [],
            )
            shadow.commands = AnimatedFactor.apply(to: carried, cutAt: cuts) {
                // Each end read at its own moment. Both taken from the start,
                // a command spanning the clip carried the offset the sprite was
                // born with for its whole length — the animation existed in the
                // document and never reached the picture.
                Self.offset(
                    $0,
                    byStart: (offsetX($0.startTime), offsetY($0.startTime)),
                    end: (offsetX($0.endTime), offsetY($0.endTime)),
                )
            }

            // Dimmed by multiplying the fades it already has, so a shadow
            // follows its subject's own fading rather than staying lit after it
            // has gone.
            shadow.commands = AnimatedFactor.apply(to: shadow.commands, cutAt: cuts) { command in
                guard case let .fade(start, end) = command.payload else { return command }
                return Command(
                    timing: command.timing,
                    payload: .fade(
                        start: start * opacity(command.startTime),
                        end: end * opacity(command.endTime),
                    ),
                )
            }
            if !sprite.commands.contains(where: { $0.kind == .fade }) {
                shadow.commands.append(Command(
                    easing: .linear, startTime: birth, endTime: birth,
                    payload: .fade(start: opacity(birth), end: opacity(birth)),
                ))
            }

            // Its own colour, replacing whatever tint the subject carried: a
            // shadow is dark, not a darker copy of the subject's hue.
            shadow.commands.removeAll { $0.kind == .color }
            let tintAt = shadow.commands.map(\.startTime).min() ?? birth
            shadow.commands.append(Command(
                easing: .linear, startTime: tintAt, endTime: tintAt,
                payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                ),
            ))

            // Behind the subject, which is the whole point — in front, it would
            // be a stain over the thing casting it.
            result.append(shadow)
            result.append(sprite)
        }

        return result
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        context.number(Param.opacity) > 0 ? 2 : 1
    }

    /// Moves every coordinate a command names.
    private static func offset(
        _ command: Command,
        byStart from: (x: Double, y: Double),
        end to: (x: Double, y: Double),
    ) -> Command {
        switch command.payload {
        case let .move(sx, sy, ex, ey):
            Command(timing: command.timing, payload: .move(
                startX: sx + from.x, startY: sy + from.y,
                endX: ex + to.x, endY: ey + to.y,
            ))
        case let .moveX(start, end):
            Command(
                timing: command.timing,
                payload: .moveX(start: start + from.x, end: end + to.x),
            )
        case let .moveY(start, end):
            Command(
                timing: command.timing,
                payload: .moveY(start: start + from.y, end: end + to.y),
            )
        default:
            command
        }
    }
}
