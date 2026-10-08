import Foundation

/// A solid line around the silhouette of whatever is on the clip.
///
/// What lyrics need over a bright background: white text over white has no
/// way out. A shadow only offsets one copy and a glow washes out on light, so
/// neither draws an edge on every side.
///
/// One copy per sprite, behind it, drawing the sprite's silhouette grown by
/// the width — a derived image, so the line costs pixels rather than the ring
/// of offset copies a shader-less outline usually takes.
public struct OutlineFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let width = "width"
        public static let colour = "colour"
        public static let opacity = "opacity"
    }

    public static let descriptor = FilterDescriptor(
        type: "outline",
        name: "Outline",
        category: .look,
        systemImage: "circle.dashed.inset.filled",
        parameters: [
            EffectParameter(
                id: Param.width, name: "Width", group: "Outline",
                defaultValue: .number(4),
                range: Double(DerivedSprite.outlineWidthRange.lowerBound)...Double(DerivedSprite.outlineWidthRange.upperBound),
                step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.colour, name: "Colour", group: "Outline",
                // Black: the case it exists for is light text over a light
                // frame, and a dark edge is what separates them.
                defaultValue: .color(EffectColor(r: 0, g: 0, b: 0)),
            ),
            EffectParameter(
                id: Param.opacity, name: "Opacity", group: "Outline",
                defaultValue: .number(1), range: 0...1, step: 0.05, presentation: .slider,
                animation: .commands,
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        draws(context) ? 2 : 1
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        guard draws(context) else { return sprites }

        let width = context.number(Param.width)
        let margin = Double(DerivedSprite.outlineMargin(width: width))
        let colour = context.color(Param.colour)
        let cuts = context.keyTimes(of: [Param.opacity])
        let opacity = { context.number(Param.opacity, at: $0) }

        let outlines = sprites.enumerated().map { index, sprite in
            outline(
                of: sprite, id: "\(context.idPrefix)/o\(index)",
                width: width, margin: margin, colour: colour, cuts: cuts, opacity: opacity,
            )
        }
        // Behind: the original covers the inside of its own outline, so only
        // the ring shows.
        return outlines + sprites
    }

    private func draws(_ context: FilterContext) -> Bool {
        context.isAnimated(Param.opacity) || context.number(Param.opacity) > 0
    }

    private func outline(
        of sprite: StoryboardSprite,
        id: String,
        width: Double,
        margin: Double,
        colour: EffectColor,
        cuts: [Double],
        opacity: @escaping (Double) -> Double,
    ) -> StoryboardSprite {
        var copy = sprite
        copy.id = id
        copy.filePath = DerivedSprite.outlined(sprite.filePath, width: width)

        let birth = sprite.commands.map(\.startTime).min() ?? 0
        let death = sprite.commands.map(\.endTime).max() ?? birth

        // Its own colour, and never additive: an outline is paint, and an
        // additive black adds nothing at all.
        copy.commands = AnimatedFactor.apply(to: sprite.commands, cutAt: cuts) { command in
            switch command.payload {
            case .color, .parameter(.additive):
                return nil
            case let .fade(start, end):
                return Command(
                    timing: command.timing,
                    payload: .fade(start: start * opacity(command.startTime), end: end * opacity(command.endTime)),
                )
            default:
                return command
            }
        }
        copy.commands.append(Command(
            easing: .linear, startTime: birth, endTime: birth,
            payload: .color(
                startR: colour.r, startG: colour.g, startB: colour.b,
                endR: colour.r, endG: colour.g, endB: colour.b,
            ),
        ))
        // A sprite with no fade of its own draws at full opacity, so there is
        // nothing for the opacity to multiply — the outline needs its own.
        if !sprite.commands.contains(where: { $0.kind == .fade }) {
            copy.commands.append(Command(
                easing: .linear, startTime: birth, endTime: death,
                payload: .fade(start: opacity(birth), end: opacity(death)),
            ))
        }

        return anchored(copy, original: sprite, margin: margin)
    }

    /// Moves the outline back onto its sprite.
    ///
    /// The outlined canvas is `margin` bigger on every side, and osu! anchors
    /// the *canvas*: a sprite hung from its top-left corner would draw its
    /// outline a margin up and to the left of the original. The difference is
    /// `margin × (1 − 2·anchor)` source pixels, scaled and turned with the
    /// sprite — read at each moment a position is written. Centred sprites
    /// need nothing.
    ///
    /// A sprite that holds still while its scale or rotation animates keeps
    /// the correction it had at birth: the position has no command to carry a
    /// changing one, and writing a move just for it would cost a command per
    /// sprite for a sub-pixel drift on most clips.
    private func anchored(_ copy: StoryboardSprite, original: StoryboardSprite, margin: Double) -> StoryboardSprite {
        let anchor = original.origin.anchor
        let fx = margin * (1 - 2 * Double(anchor.x))
        let fy = margin * (1 - 2 * Double(anchor.y))
        guard fx != 0 || fy != 0 else { return copy }

        let shift = { (time: Double) -> (x: Double, y: Double) in
            let scale = original.restingScale(at: time)
            let x = -fx * scale.x
            let y = -fy * scale.y
            let turn = original.restingRotation(at: time)
            return (x * cos(turn) - y * sin(turn), x * sin(turn) + y * cos(turn))
        }

        var moved = copy
        let birth = original.commands.map(\.startTime).min() ?? 0
        let atBirth = shift(birth)
        moved.defaultX += atBirth.x
        moved.defaultY += atBirth.y

        moved.commands = copy.commands.map { command in
            let a = shift(command.startTime)
            let b = shift(command.endTime)
            switch command.payload {
            case let .move(startX, startY, endX, endY):
                return Command(timing: command.timing, payload: .move(
                    startX: startX + a.x, startY: startY + a.y, endX: endX + b.x, endY: endY + b.y,
                ))
            case let .moveX(start, end):
                return Command(timing: command.timing, payload: .moveX(start: start + a.x, end: end + b.x))
            case let .moveY(start, end):
                return Command(timing: command.timing, payload: .moveY(start: start + a.y, end: end + b.y))
            default:
                return command
            }
        }
        return moved
    }
}
