import Foundation

/// The clip re-drawn as a print's dot screen: one dot per cell, sized by how
/// much ink the cell holds.
///
/// Where LED lights or darkens a cell, this grades it — the look of newsprint
/// and comic shading rather than of a sign. One image per sprite, the same
/// size as its source, so nothing moves and nothing is added.
public struct HalftoneFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let cell = "cell"
        public static let shape = "shape"
    }

    public enum Shape {
        public static let round = "Round"
        public static let square = "Square"
    }

    public static let descriptor = FilterDescriptor(
        type: "halftone",
        name: "Halftone",
        category: .look,
        systemImage: "circle.grid.3x3.fill",
        parameters: [
            EffectParameter(
                id: Param.cell, name: "Cell", group: "Halftone",
                defaultValue: .number(8),
                range: Double(DerivedSprite.dotPitchRange.lowerBound)...Double(DerivedSprite.dotPitchRange.upperBound),
                step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.shape, name: "Dot", group: "Halftone",
                defaultValue: .choice(Shape.round), options: [Shape.round, Shape.square],
            ),
        ],
    )

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let cell = context.number(Param.cell)
        let shape: DerivedSprite.DotShape = context.choice(Param.shape) == Shape.square ? .square : .round
        return sprites.map { sprite in
            var swapped = sprite
            swapped.filePath = DerivedSprite.halftone(sprite.filePath, cell: cell, shape: shape)
            return swapped
        }
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }
}
