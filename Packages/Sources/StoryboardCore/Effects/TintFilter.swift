import Foundation

/// Recolours everything a clip draws.
///
/// One sprite in, one sprite out: a tint is a `_C` command, not a copy. That
/// makes it the cheapest thing in the library — the whole look of a clip
/// changes for one command per sprite.
///
/// It replaces whatever colour the sprites carried rather than multiplying with
/// it. Two tints stacking would darken with every layer, and "tint this clip
/// blue" is a statement about the result, not a filter over a filter.
public struct TintFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let colour = "colour"
        public static let endColour = "endColour"
        public static let overTime = "overTime"
    }

    public static let descriptor = FilterDescriptor(
        type: "tint",
        name: "Tint",
        category: "Stylise",
        systemImage: "paintpalette",
        parameters: [
            EffectParameter(
                id: Param.colour, name: "Colour", group: "Tint",
                defaultValue: .color(EffectColor(r: 255, g: 180, b: 120)),
            ),
            EffectParameter(
                id: Param.overTime, name: "Over Time", group: "Tint",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.endColour, name: "To", group: "Tint",
                defaultValue: .color(EffectColor(r: 120, g: 160, b: 255)),
            ),
        ],
    )

    public func apply(
        to sprites: [StoryboardSprite],
        in context: FilterContext,
    ) -> [StoryboardSprite] {
        let start = context.color(Param.colour)
        let end = context.toggle(Param.overTime) ? context.color(Param.endColour) : start

        return sprites.map { sprite in
            var tinted = sprite
            // Replaced, not layered: the clip's colour is one decision.
            tinted.commands.removeAll { $0.kind == .color }

            // Over the sprite's own life, not the clip's. A particle that lives
            // for half a second should travel the whole ramp in that time —
            // spread over the clip instead, every particle would show the same
            // sliver of it and the gradient would be invisible.
            let birth = sprite.commands.map(\.startTime).min() ?? 0
            let death = sprite.commands.map(\.endTime).max() ?? birth

            tinted.commands.append(Command(
                easing: .linear,
                startTime: birth,
                endTime: start == end ? birth : death,
                payload: .color(
                    startR: start.r, startG: start.g, startB: start.b,
                    endR: end.r, endG: end.g, endB: end.b,
                ),
            ))
            return tinted
        }
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }
}
