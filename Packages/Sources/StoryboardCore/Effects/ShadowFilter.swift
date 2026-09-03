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
            ),
            EffectParameter(
                id: Param.offsetY, name: "Offset Y", group: "Shadow",
                defaultValue: .number(6), range: -200...200, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.opacity, name: "Opacity", group: "Shadow",
                defaultValue: .number(0.5), range: 0...1, step: 0.05,
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
        let offsetX = context.number(Param.offsetX)
        let offsetY = context.number(Param.offsetY)
        let opacity = context.number(Param.opacity)
        let softness = context.number(Param.softness)
        let colour = context.color(Param.colour)

        guard opacity > 0, offsetX != 0 || offsetY != 0 || softness > 0 else { return sprites }

        var result: [StoryboardSprite] = []
        result.reserveCapacity(sprites.count * 2)

        for sprite in sprites {
            var shadow = sprite
            shadow.id = "\(context.idPrefix)/shadow-\(sprite.id)"
            shadow.defaultX += offsetX
            shadow.defaultY += offsetY

            if softness > 0 {
                shadow.filePath = DerivedSprite.blurred(sprite.filePath, radius: softness)
            }

            // Every coordinate the commands name moves with it, or a sprite
            // that travels leaves its shadow behind at the starting point.
            shadow.commands = sprite.commands.map { Self.offset($0, by: offsetX, offsetY) }

            // Dimmed by multiplying the fades it already has, so a shadow
            // follows its subject's own fading rather than staying lit after it
            // has gone.
            shadow.commands = shadow.commands.map { command in
                guard case let .fade(start, end) = command.payload else { return command }
                return Command(
                    timing: command.timing,
                    payload: .fade(start: start * opacity, end: end * opacity),
                )
            }
            if !sprite.commands.contains(where: { $0.kind == .fade }) {
                let birth = sprite.commands.map(\.startTime).min() ?? 0
                shadow.commands.append(Command(
                    easing: .linear, startTime: birth, endTime: birth,
                    payload: .fade(start: opacity, end: opacity),
                ))
            }

            // Its own colour, replacing whatever tint the subject carried: a
            // shadow is dark, not a darker copy of the subject's hue.
            shadow.commands.removeAll { $0.kind == .color }
            let birth = shadow.commands.map(\.startTime).min() ?? 0
            shadow.commands.append(Command(
                easing: .linear, startTime: birth, endTime: birth,
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
    private static func offset(_ command: Command, by x: Double, _ y: Double) -> Command {
        switch command.payload {
        case let .move(sx, sy, ex, ey):
            Command(timing: command.timing, payload: .move(
                startX: sx + x, startY: sy + y, endX: ex + x, endY: ey + y,
            ))
        case let .moveX(start, end):
            Command(timing: command.timing, payload: .moveX(start: start + x, end: end + x))
        case let .moveY(start, end):
            Command(timing: command.timing, payload: .moveY(start: start + y, end: end + y))
        default:
            command
        }
    }
}
