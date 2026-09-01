import Foundation

/// Reflects a clip across the stage.
///
/// Symmetry is a visual shortcut that never stops working, and a mirror is the
/// cheapest way to it: one copy, flipped. Distinct from Radial Repeat with two
/// arms, which *rotates* — a rotated copy of a hand is another right hand, a
/// mirrored one is a left. On anything with a direction the difference is the
/// whole point.
public struct MirrorFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let axis = "axis"
        public static let offset = "offset"
        public static let opacity = "opacity"
    }

    public enum Axis: String, CaseIterable, Sendable {
        case horizontal = "Horizontal"
        case vertical = "Vertical"
        case both = "Both"
    }

    public static let descriptor = FilterDescriptor(
        type: "mirror",
        name: "Mirror",
        category: "Stylise",
        systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
        parameters: [
            EffectParameter(
                id: Param.axis,
                name: "Axis",
                group: "Mirror",
                defaultValue: .choice(Axis.horizontal.rawValue),
                options: Axis.allCases.map(\.rawValue),
            ),
            // Where the mirror stands, measured from the stage centre.
            //
            // A reflection needs a line to reflect about, and the middle is
            // only the obvious choice when the subject is centred too.
            EffectParameter(
                id: Param.offset,
                name: "Axis Offset",
                group: "Mirror",
                defaultValue: .number(0),
                range: -400...400,
                step: 10,
                unit: "px",
            ),
            // A dimmer reflection reads as one — a surface, water, a shadow on
            // glass. At full strength the pair reads as two of the thing.
            EffectParameter(
                id: Param.opacity,
                name: "Reflection",
                group: "Mirror",
                defaultValue: .number(1),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        context.choice(Param.axis) == Axis.both.rawValue ? 4 : 2
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let axis = Axis(rawValue: context.choice(Param.axis)) ?? .horizontal
        let offset = context.number(Param.offset)
        let opacity = context.number(Param.opacity)

        let flips: [(x: Bool, y: Bool)] = switch axis {
        case .horizontal: [(true, false)]
        case .vertical: [(false, true)]
        // Both axes gives three reflections, not two: the diagonal one is what
        // closes the figure. Left out, the result is an L rather than a square.
        case .both: [(true, false), (false, true), (true, true)]
        }

        var result = sprites
        result.reserveCapacity(sprites.count * (flips.count + 1))

        for (flipIndex, flip) in flips.enumerated() {
            for (index, sprite) in sprites.enumerated() {
                var copy = sprite
                copy.id = "\(context.idPrefix)/m\(flipIndex)-\(index)"
                copy.defaultX = mirroredX(sprite.defaultX, flip: flip, offset: offset)
                copy.defaultY = mirroredY(sprite.defaultY, flip: flip, offset: offset)

                copy.commands = sprite.commands.compactMap { command in
                    mirror(command, flip: flip, offset: offset, opacity: opacity)
                }

                // The image itself has to turn over too, or a reflection of an
                // arrow still points the same way — the positions would be
                // mirrored while every sprite in them was not.
                copy.commands.append(Command(
                    easing: .linear,
                    startTime: sprite.commands.map(\.startTime).min() ?? 0,
                    endTime: sprite.commands.map(\.startTime).min() ?? 0,
                    payload: .parameter(flip.x ? .flipHorizontal : .flipVertical),
                ))
                if flip.x, flip.y {
                    copy.commands.append(Command(
                        easing: .linear,
                        startTime: sprite.commands.map(\.startTime).min() ?? 0,
                        endTime: sprite.commands.map(\.startTime).min() ?? 0,
                        payload: .parameter(.flipVertical),
                    ))
                }

                result.append(copy)
            }
        }

        return result
    }

    private func mirroredX(_ x: Double, flip: (x: Bool, y: Bool), offset: Double) -> Double {
        guard flip.x else { return x }
        let line = TransformProperty.x.defaultValue + offset
        return 2 * line - x
    }

    private func mirroredY(_ y: Double, flip: (x: Bool, y: Bool), offset: Double) -> Double {
        guard flip.y else { return y }
        let line = TransformProperty.y.defaultValue + offset
        return 2 * line - y
    }

    private func mirror(
        _ command: Command,
        flip: (x: Bool, y: Bool),
        offset: Double,
        opacity: Double,
    ) -> Command {
        var copy = command
        switch command.payload {
        case let .move(startX, startY, endX, endY):
            copy.payload = .move(
                startX: mirroredX(startX, flip: flip, offset: offset),
                startY: mirroredY(startY, flip: flip, offset: offset),
                endX: mirroredX(endX, flip: flip, offset: offset),
                endY: mirroredY(endY, flip: flip, offset: offset),
            )

        case let .moveX(start, end) where flip.x:
            copy.payload = .moveX(
                start: mirroredX(start, flip: flip, offset: offset),
                end: mirroredX(end, flip: flip, offset: offset),
            )

        case let .moveY(start, end) where flip.y:
            copy.payload = .moveY(
                start: mirroredY(start, flip: flip, offset: offset),
                end: mirroredY(end, flip: flip, offset: offset),
            )

        // A reflection turns the other way: mirrored, a clockwise spin is
        // anticlockwise, and leaving it alone is what makes a pair of mirrored
        // sprites drift out of symmetry the moment either one turns.
        case let .rotate(start, end):
            copy.payload = flip.x != flip.y
                ? .rotate(start: -start, end: -end)
                : command.payload

        case let .fade(start, end) where opacity < 1:
            copy.payload = .fade(start: start * opacity, end: end * opacity)

        default:
            break
        }
        return copy
    }
}
