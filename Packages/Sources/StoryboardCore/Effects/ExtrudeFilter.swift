import Foundation

/// Gives a flat clip thickness: copies stacked behind it, each a step further
/// back and a shade darker, so a title reads as a block rather than a sticker.
///
/// The classic 3D-title trick, and the only one a storyboard can do — there
/// is no geometry to extrude, so the side is the face repeated. Every copy is
/// a sprite, which is the cost, and it is named in the multiplier.
///
/// All the copies draw before all the faces, so on a line of text one
/// letter's side never covers the next letter's face.
public struct ExtrudeFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let steps = "steps"
        public static let depth = "depth"
        public static let angle = "angle"
        public static let colour = "colour"
        public static let shade = "shade"
    }

    public static let descriptor = FilterDescriptor(
        type: "extrude",
        name: "Extrude",
        category: .threeD,
        systemImage: "square.3.layers.3d.down.right",
        parameters: [
            EffectParameter(
                id: Param.steps, name: "Steps", group: "Extrude",
                // Enough that the side reads solid at the default depth: two
                // pixels apart, the copies close up.
                defaultValue: .integer(6), range: 1...16, step: 1,
            ),
            EffectParameter(id: Param.depth, name: "Depth", group: "Extrude", defaultValue: .number(12), range: 0...100, step: 1, unit: "px"),
            EffectParameter(
                id: Param.angle, name: "Direction", group: "Extrude",
                // Down and to the right: light from the top left, as a reader
                // expects it.
                defaultValue: .number(45), range: -180...180, step: 5, unit: "°",
            ),
            EffectParameter(id: Param.colour, name: "Side Colour", group: "Extrude", defaultValue: .color(EffectColor(r: 70, g: 60, b: 110))),
            EffectParameter(id: Param.shade, name: "Shade", group: "Extrude", defaultValue: .number(0.5), range: 0...1, step: 0.05, presentation: .slider),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        context.number(Param.depth) > 0 ? Double(max(1, context.integer(Param.steps)) + 1) : 1
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let depth = context.number(Param.depth)
        guard depth > 0 else { return sprites }
        let steps = max(1, context.integer(Param.steps))
        let angle = context.number(Param.angle) * .pi / 180
        let colour = context.color(Param.colour)
        let shade = context.number(Param.shade)

        // Farthest first: draw order is the only depth a storyboard has.
        var sides: [StoryboardSprite] = []
        for step in stride(from: steps, through: 1, by: -1) {
            let fraction = Double(step) / Double(steps)
            let offset = (x: cos(angle) * depth * fraction, y: sin(angle) * depth * fraction)
            let tone = 1 - shade * fraction
            let tint = EffectColor(r: colour.r * tone, g: colour.g * tone, b: colour.b * tone)
            for (index, sprite) in sprites.enumerated() {
                sides.append(side(of: sprite, id: "\(context.idPrefix)/e\(step)/\(index)", offset: offset, tint: tint))
            }
        }
        return sides + sprites
    }

    private func side(
        of sprite: StoryboardSprite, id: String, offset: (x: Double, y: Double), tint: EffectColor,
    ) -> StoryboardSprite {
        var copy = sprite
        copy.id = id
        copy.defaultX += offset.x
        copy.defaultY += offset.y
        // Paint, not light: its own colour and never additive.
        copy.commands = sprite.commands.compactMap { command in
            switch command.payload {
            case .color, .parameter(.additive):
                return nil
            case let .move(sx, sy, ex, ey):
                return Command(timing: command.timing, payload: .move(
                    startX: sx + offset.x, startY: sy + offset.y, endX: ex + offset.x, endY: ey + offset.y,
                ))
            case let .moveX(start, end):
                return Command(timing: command.timing, payload: .moveX(start: start + offset.x, end: end + offset.x))
            case let .moveY(start, end):
                return Command(timing: command.timing, payload: .moveY(start: start + offset.y, end: end + offset.y))
            default:
                return command
            }
        }
        let birth = sprite.commands.map(\.startTime).min() ?? 0
        copy.commands.append(Command(easing: .linear, startTime: birth, endTime: birth, payload: .color(
            startR: tint.r, startG: tint.g, startB: tint.b, endR: tint.r, endG: tint.g, endB: tint.b,
        )))
        return copy
    }
}
