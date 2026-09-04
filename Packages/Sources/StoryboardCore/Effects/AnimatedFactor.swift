import Foundation

/// Applies a value that changes over time to commands that were being written
/// anyway.
///
/// This is the whole trick behind keyframing a filter cheaply. A filter like
/// ``GlowFilter`` scales a sprite's fades by an intensity; a still intensity is
/// one multiplication and costs nothing. An *animated* one cannot simply be
/// sampled once — that is the mistake this project has already made twice, with
/// opacity and with scale on ``GroupTransform``:
///
/// > A property that animates needs commands of its own, not a factor.
///
/// Read at a single instant, the factor freezes at whatever it was when the
/// sprite was born while the inspector shows the number moving. So the factor
/// is read at **both ends of every command**, and any command a keyframe falls
/// inside is cut at that keyframe first — otherwise the key's curve is lost
/// inside a span the underlying command drew.
///
/// The cost is one extra command per keyframe crossed, and nothing at all when
/// nobody is animating: with no cut times the commands come back one for one.
public enum AnimatedFactor {
    /// Rewrites `commands`, cutting each at the moments a factor changes so the
    /// rewrite can read its factors at each piece's own ends.
    ///
    /// The transform is handed whole pieces rather than pre-sampled numbers
    /// because a filter usually scales several payloads by *different* factors
    /// — a glow's intensity drives its fades while its size drives its scales —
    /// and one factor argument could only serve one of them.
    ///
    /// - Parameters:
    ///   - commands: the sprite's commands, in whatever order they were built.
    ///   - times: the keyframe moments any animated factor changes at, in clip
    ///     time. Empty means nothing animates and nothing is cut.
    ///   - transform: builds a command from one piece, reading its factors at
    ///     `piece.startTime` and `piece.endTime`. Returning `nil` drops it, as
    ///     a filter dropping a duplicate command already does.
    public static func apply(
        to commands: [Command],
        cutAt times: [Double],
        transform: (Command) -> Command?,
    ) -> [Command] {
        commands.flatMap { command in
            split(command, at: times).compactMap(transform)
        }
    }

    /// One command cut into pieces at every moment falling strictly inside it.
    ///
    /// Strictly inside: a key exactly on a boundary already is one, and cutting
    /// there would leave a zero-length piece — a command starting and ending at
    /// the same instant, which reads as an instant set rather than as part of
    /// the interpolation it came from.
    static func split(_ command: Command, at times: [Double]) -> [Command] {
        let span = command.endTime - command.startTime
        guard span > 0 else { return [command] }

        let inside = times.filter { $0 > command.startTime && $0 < command.endTime }.sorted()
        guard !inside.isEmpty else { return [command] }

        let bounds = [command.startTime] + inside + [command.endTime]
        return zip(bounds, bounds.dropFirst()).map { from, to in
            sliced(command, from: from, to: to, span: span)
        }
    }

    /// The stretch of a command between two moments.
    ///
    /// The pieces are linear because the original curve is expressed by *where
    /// each piece lands*, not by each piece repeating it: an easing applies
    /// across whatever span it is given, so carrying it onto every piece would
    /// restart the curve at each cut and turn one ease into a row of them.
    private static func sliced(
        _ command: Command,
        from: Double,
        to: Double,
        span: Double,
    ) -> Command {
        let a = easedLerp(0, 1, (from - command.startTime) / span, command.easing)
        let b = easedLerp(0, 1, (to - command.startTime) / span, command.easing)

        func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
            start + (end - start) * t
        }

        var piece = command
        piece.timing.startTime = from
        piece.timing.endTime = to
        piece.timing.easing = .linear

        switch command.payload {
        case let .fade(start, end):
            piece.payload = .fade(start: lerp(start, end, a), end: lerp(start, end, b))

        case let .scale(start, end):
            piece.payload = .scale(start: lerp(start, end, a), end: lerp(start, end, b))

        case let .vectorScale(startX, startY, endX, endY):
            piece.payload = .vectorScale(
                startX: lerp(startX, endX, a), startY: lerp(startY, endY, a),
                endX: lerp(startX, endX, b), endY: lerp(startY, endY, b),
            )

        case let .move(startX, startY, endX, endY):
            piece.payload = .move(
                startX: lerp(startX, endX, a), startY: lerp(startY, endY, a),
                endX: lerp(startX, endX, b), endY: lerp(startY, endY, b),
            )

        case let .moveX(start, end):
            piece.payload = .moveX(start: lerp(start, end, a), end: lerp(start, end, b))

        case let .moveY(start, end):
            piece.payload = .moveY(start: lerp(start, end, a), end: lerp(start, end, b))

        case let .rotate(start, end):
            piece.payload = .rotate(start: lerp(start, end, a), end: lerp(start, end, b))

        case let .color(startR, startG, startB, endR, endG, endB):
            piece.payload = .color(
                startR: lerp(startR, endR, a), startG: lerp(startG, endG, a),
                startB: lerp(startB, endB, a),
                endR: lerp(startR, endR, b), endG: lerp(startG, endG, b),
                endB: lerp(startB, endB, b),
            )

        // A parameter is a flag held for a span, not a value travelling between
        // two — there is nothing to interpolate, and each piece holds it just
        // as the original did.
        case .parameter:
            break
        }
        return piece
    }
}
