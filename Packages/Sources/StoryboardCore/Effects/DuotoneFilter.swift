import Foundation

/// The clip's light and shade mapped onto two colours.
///
/// Tint can only multiply: a white sprite tinted blue is blue, and its shadows
/// stay black. A duotone puts a colour in the shadows too, which is what makes
/// a photo read as a poster. It has to be baked into the image — `_C`
/// multiplies a texture, it cannot remap it.
public struct DuotoneFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let dark = "dark"
        public static let light = "light"
    }

    public static let descriptor = FilterDescriptor(
        type: "duotone",
        name: "Duotone",
        category: .look,
        systemImage: "circle.lefthalf.filled",
        parameters: [
            EffectParameter(
                id: Param.dark, name: "Shadows", group: "Duotone",
                defaultValue: .color(EffectColor(r: 30, g: 20, b: 90)),
            ),
            EffectParameter(
                id: Param.light, name: "Highlights", group: "Duotone",
                defaultValue: .color(EffectColor(r: 255, g: 200, b: 90)),
            ),
        ],
    )

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let dark = context.color(Param.dark)
        let light = context.color(Param.light)
        return sprites.map { sprite in
            var swapped = sprite
            swapped.filePath = DerivedSprite.duotone(sprite.filePath, dark: dark, light: light)
            return swapped
        }
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }
}
