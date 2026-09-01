import Foundation

/// Replays a clip faster, slower, or backwards.
///
/// The cheapest filter in the library and the one that adds the most: it writes
/// nothing new, it only moves the times already written. Slow motion, a
/// double-speed burst and a rewind are three transformations that no parameter
/// on an effect can express, and all three cost **not one extra sprite**.
///
/// Speed rather than a target duration, because a clip's length is already the
/// thing being edited on the timeline: told to fill a length, the filter would
/// fight the drag handles for the same number.
public struct TimeFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let speed = "speed"
        public static let reverse = "reverse"
    }

    public static let descriptor = FilterDescriptor(
        type: "time",
        name: "Time",
        category: "Time",
        systemImage: "gauge.with.needle",
        parameters: [
            EffectParameter(
                id: Param.speed,
                name: "Speed",
                group: "Time",
                defaultValue: .number(1),
                range: 0.1...4,
                step: 0.05,
                unit: "×",
            ),
            EffectParameter(
                id: Param.reverse,
                name: "Reverse",
                group: "Time",
                defaultValue: .toggle(false),
            ),
        ],
    )

    /// Faster finishes sooner and slower runs on, which is the whole point of
    /// the filter and the reason it has to report it: a clip that plays for
    /// four times its block is one nobody can arrange the rest against.
    public func duration(of clipDuration: Double, in context: FilterContext) -> Double {
        clipDuration / max(0.01, context.number(Param.speed))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let speed = max(0.01, context.number(Param.speed))
        let reverse = context.toggle(Param.reverse)

        guard speed != 1 || reverse else { return sprites }

        // Reversal turns on the clip's own span, not on each sprite's.
        //
        // Mirroring every sprite about its own first command would leave each
        // one playing backwards in place while the arrangement between them
        // stayed as it was — particles born late would still be born late. What
        // reads as rewinding is that the whole thing runs the other way, so the
        // pivot has to be shared.
        let span = sprites.flatMap { sprite in
            sprite.commands.map(\.endTime) + sprite.loops.map(\.startTime)
        }.max() ?? 0

        return sprites.map { sprite in
            var moved = sprite
            moved.commands = sprite.commands.map { remap($0, speed: speed, reverse: reverse, span: span) }
            moved.loops = sprite.loops.map { loop in
                var shifted = loop
                shifted.startTime = time(loop.startTime, speed: speed, reverse: reverse, span: span)
                // A loop body is relative to its own iteration, so it is scaled
                // but never mirrored: reversing inside the body would fight the
                // repeat, which always plays forwards.
                shifted.commands = loop.commands.map {
                    remap($0, speed: speed, reverse: false, span: 0)
                }
                return shifted
            }
            return moved
        }
    }

    private func remap(
        _ command: Command,
        speed: Double,
        reverse: Bool,
        span: Double,
    ) -> Command {
        var moved = command
        let start = time(command.startTime, speed: speed, reverse: reverse, span: span)
        let end = time(command.endTime, speed: speed, reverse: reverse, span: span)

        // Reversed, a command runs from what used to be its end.
        moved.timing.startTime = min(start, end)
        moved.timing.endTime = max(start, end)

        // And its values run the other way too — a fade that rose now falls.
        // Without this the sprite would sit at the right moments doing the
        // wrong thing, which is the half of "backwards" that is easy to miss.
        if reverse {
            moved.payload = command.payload.reversed
        }
        return moved
    }

    private func time(_ at: Double, speed: Double, reverse: Bool, span: Double) -> Double {
        (reverse ? span - at : at) / speed
    }
}
