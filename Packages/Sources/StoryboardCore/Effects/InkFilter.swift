import Foundation

/// The clip drawn as its edges: the outer contour, and the inner ones as far
/// as `Detail` lets them in.
///
/// `Lines` replaces the image and keeps the sprite's colour — white line art
/// on a dark stage. `Over Original` keeps the image and inks it, the comic
/// look, at the cost of a copy per sprite.
public struct InkFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let width = "width"
        public static let detail = "detail"
        public static let mode = "mode"
        public static let colour = "colour"
    }

    public enum Mode: String, CaseIterable, Sendable {
        case lines = "Lines"
        case over = "Over Original"
    }

    public static let descriptor = FilterDescriptor(
        type: "ink",
        name: "Ink",
        category: .look,
        systemImage: "pencil.and.outline",
        parameters: [
            EffectParameter(
                id: Param.mode, name: "Mode", group: "Ink",
                defaultValue: .choice(Mode.lines.rawValue), options: Mode.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: Param.width, name: "Width", group: "Ink",
                defaultValue: .number(2),
                range: Double(DerivedSprite.inkWidthRange.lowerBound)...Double(DerivedSprite.inkWidthRange.upperBound),
                step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.detail, name: "Detail", group: "Ink",
                defaultValue: .number(0.3), range: 0...1, step: 0.05, presentation: .slider,
            ),
            EffectParameter(
                id: Param.colour, name: "Line Colour", group: "Ink",
                defaultValue: .color(EffectColor(r: 0, g: 0, b: 0)),
                // Lines alone keep the sprite's colour; a separate one only
                // means something over the original.
                shownWhen: .init(parameter: Param.mode, isAnyOf: [Mode.over.rawValue]),
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        context.choice(Param.mode) == Mode.over.rawValue ? 2 : 1
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let width = context.number(Param.width)
        let detail = context.number(Param.detail)

        guard context.choice(Param.mode) == Mode.over.rawValue else {
            return sprites.map { sprite in
                let resolution = DerivedSprite.lineResolution(for: sprite.filePath)
                var swapped = sprite
                swapped.filePath = DerivedSprite.inked(sprite.filePath, width: width, detail: detail, resolution: resolution)
                // Drawn larger, shown smaller: the same size on screen, with
                // the lines finer than a storyboard pixel.
                return swapped.scaled(by: 1 / Double(resolution))
            }
        }

        let colour = context.color(Param.colour)
        let lines = sprites.enumerated().map { index, sprite in
            var copy = sprite
            copy.id = "\(context.idPrefix)/i\(index)"
            let resolution = DerivedSprite.lineResolution(for: sprite.filePath)
            copy.filePath = DerivedSprite.inked(sprite.filePath, width: width, detail: detail, resolution: resolution)
            // Ink is paint: its own colour, never added as light.
            copy.commands.removeAll { $0.kind == .color || $0.payload.isAdditive }
            let birth = sprite.commands.map(\.startTime).min() ?? 0
            copy.commands.append(Command(
                easing: .linear, startTime: birth, endTime: birth,
                payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                ),
            ))
            return copy.scaled(by: 1 / Double(resolution))
        }
        // On top: lines under their own fill would be covered by it.
        return sprites + lines
    }
}

private extension Command.Payload {
    var isAdditive: Bool {
        if case .parameter(.additive) = self { return true }
        return false
    }
}
