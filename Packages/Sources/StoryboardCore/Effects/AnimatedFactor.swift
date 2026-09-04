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
        commands.flatMap { command -> [Command] in
            // A command the transform hands back untouched is left exactly as
            // it was — not cut, and not flattened.
            //
            // Cutting re-expresses a curve as a row of straight pieces, which
            // is fine for a command whose values this is about to rewrite and
            // wrong for one it only passes along. A glow copies its subject's
            // movement verbatim, so slicing an eased `_M` left the halo
            // travelling in chords while the sprite followed the curve:
            // measured, **30px apart** at the middle of each piece and meeting
            // again at every cut. The halo trailed its own sprite.
            //
            // Decided by **kind**, not by comparing values: a factor that
            // happens to leave one command's numbers alone — multiplying a fade
            // that starts at zero, say — still has to cut it, or the rest of
            // that command carries the factor from its far end. An earlier
            // version compared the rewritten command to the original and got
            // exactly that wrong.
            guard let rewritten = transform(command) else { return [] }
            guard rewritten.kind == command.kind else {
                // A filter that changes what a command *is* has rewritten it by
                // definition.
                return split(command, at: times).compactMap(transform)
            }
            if !isRewritten(command, by: transform) { return [command] }

            return split(command, at: times).compactMap(transform)
        }
    }

    /// Whether a filter actually touches a command, rather than passing it on.
    ///
    /// Probed with a **deliberately altered copy**: a filter that rewrites a
    /// payload will produce different numbers from different input, while one
    /// that hands the command back gives back whatever it was handed. Comparing
    /// the real result against the real input cannot tell those apart — a
    /// factor multiplying a fade that starts at zero leaves zero either way,
    /// and skipping the cut there strands the rest of the command on the
    /// factor's far value.
    ///
    /// This matters because cutting is destructive to curves: it re-expresses
    /// one eased command as a row of chords, which is right for a command whose
    /// values are about to be rewritten and wrong for one only being copied.
    private static func isRewritten(
        _ command: Command,
        by transform: (Command) -> Command?,
    ) -> Bool {
        // Values a filter is unlikely to leave untouched, and far from the
        // zeros and ones that make a multiplication invisible.
        let probe = Command(
            timing: command.timing,
            payload: perturbed(command.payload),
        )
        guard let result = transform(probe) else { return true }
        if !samePayload(result.payload, probe.payload) { return true }

        // Probed again at a **different moment**, because a factor of exactly
        // one leaves the numbers alone: a glow whose size rests at 1 looked
        // like a filter that only copies, so its animated size never got the
        // cuts it needed and never travelled. What matters is whether the
        // output depends on *when* it is asked, not on whether one sample
        // happens to change anything.
        var later = probe
        later.timing.startTime = probe.startTime + 1
        later.timing.endTime = probe.endTime + 1
        guard let shifted = transform(later) else { return true }
        return !samePayload(shifted.payload, later.payload)
    }

    /// The same kind of payload with distinctive values in it.
    private static func perturbed(_ payload: Command.Payload) -> Command.Payload {
        switch payload {
        case .fade: .fade(start: 0.37, end: 0.61)
        case .scale: .scale(start: 0.37, end: 0.61)
        case .moveX: .moveX(start: 37, end: 61)
        case .moveY: .moveY(start: 37, end: 61)
        case .rotate: .rotate(start: 0.37, end: 0.61)
        case .move: .move(startX: 37, startY: 41, endX: 61, endY: 67)
        case .vectorScale:
            .vectorScale(startX: 0.37, startY: 0.41, endX: 0.61, endY: 0.67)
        case .color:
            .color(
                startR: 37, startG: 41, startB: 43,
                endR: 61, endG: 67, endB: 71,
            )
        case let .parameter(kind): .parameter(kind)
        }
    }

    private static func samePayload(_ a: Command.Payload, _ b: Command.Payload) -> Bool {
        switch (a, b) {
        case let (.fade(a0, a1), .fade(b0, b1)):
            a0 == b0 && a1 == b1
        case let (.scale(a0, a1), .scale(b0, b1)):
            a0 == b0 && a1 == b1
        case let (.moveX(a0, a1), .moveX(b0, b1)):
            a0 == b0 && a1 == b1
        case let (.moveY(a0, a1), .moveY(b0, b1)):
            a0 == b0 && a1 == b1
        case let (.rotate(a0, a1), .rotate(b0, b1)):
            a0 == b0 && a1 == b1
        case let (.move(a0, a1, a2, a3), .move(b0, b1, b2, b3)):
            a0 == b0 && a1 == b1 && a2 == b2 && a3 == b3
        case let (.vectorScale(a0, a1, a2, a3), .vectorScale(b0, b1, b2, b3)):
            a0 == b0 && a1 == b1 && a2 == b2 && a3 == b3
        case let (.color(a0, a1, a2, a3, a4, a5), .color(b0, b1, b2, b3, b4, b5)):
            a0 == b0 && a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5
        case let (.parameter(a0), .parameter(b0)):
            a0 == b0
        default:
            false
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
