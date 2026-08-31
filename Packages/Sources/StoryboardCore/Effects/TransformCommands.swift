import Foundation

/// Turns a ``Transform`` into storyboard commands.
///
/// The two models line up almost exactly: a storyboard command interpolates one
/// property between two values with its own easing, which is precisely a
/// segment between two keyframes. So a track of *n* keys becomes *n−1*
/// commands, and nothing is approximated.
///
/// The one place they differ is X and Y. A keyframe track holds them
/// separately, since animating one without the other is ordinary; `_M` carries
/// both. Whether that becomes `_M`, `_MX` or `_MY` depends on which of them the
/// effect actually animates.
public enum TransformCommands {
    /// Commands for everything a transform animates, in local time.
    ///
    /// - Parameter duration: the clip's length, for properties held constant —
    ///   a single keyframe still has to reach the file, or the sprite draws at
    ///   its default instead.
    public static func build(from transform: Transform, duration: Double) -> [Command] {
        var commands: [Command] = []

        commands.append(contentsOf: positionCommands(transform, duration: duration))
        commands.append(contentsOf: buildScale(
            x: transform[.scaleX],
            y: transform[.scaleY],
            restingX: transform[value: .scaleX],
            restingY: transform[value: .scaleY],
            duration: duration,
        ))
        commands.append(contentsOf: propertyCommands(
            transform, .rotation, duration: duration,
            // Degrees in the editor, radians in the file.
            payload: { .rotate(start: $0 * .pi / 180, end: $1 * .pi / 180) },
        ))
        commands.append(contentsOf: propertyCommands(
            transform, .opacity, duration: duration,
            payload: { .fade(start: $0, end: $1) },
        ))

        return commands
    }

    /// Commands for one property, animated or held.
    ///
    /// An unanimated property still reaches the file when its resting value is
    /// not the default — a sprite set to half scale and never animated has to
    /// say so somewhere.
    /// Scale commands for one clip, `_S` or `_V` as the axes require.
    ///
    /// The two axes share a command, so they cannot be built independently: a
    /// `_V` carries both, and a segment boundary on either axis has to be one
    /// for both or the other axis's curve is lost inside it — the same rule
    /// position already follows for `_M`.
    ///
    /// When the axes agree throughout, `_S` is written instead. It says the
    /// same thing in one number rather than two, and a storyboard pays for
    /// every number in it.
    public static func buildScale(
        x: KeyframeTrack,
        y: KeyframeTrack,
        restingX: Double,
        restingY: Double,
        duration: Double,
    ) -> [Command] {
        let animatesX = x.isActive
        let animatesY = y.isActive

        // Neither animates: one command holding whatever they rest at, and
        // nothing at all when they rest at the default.
        guard animatesX || animatesY else {
            guard restingX != 1 || restingY != 1 else { return [] }

            // An axis left at 1 while the other was set follows it: setting
            // "scale" from one field is the ordinary case, and it must not
            // arrive in the file as a stretch.
            let valueX = restingX == 1 ? restingY : restingX
            let valueY = restingY == 1 ? restingX : restingY

            return [Command(
                easing: .linear, startTime: 0, endTime: 0,
                payload: valueX == valueY
                    ? .scale(start: valueX, end: valueX)
                    : .vectorScale(
                        startX: valueX, startY: valueY,
                        endX: valueX, endY: valueY,
                    ),
            )]
        }

        // An axis that is neither animated nor set follows the other.
        //
        // Scaling uniformly is the common case, and it reaches here as one axis
        // animating while the other rests at 1. Read literally that is a
        // stretch, and it wrote `_V` — two numbers, every time, for a sprite
        // that was only ever getting bigger. Treating an untouched axis as
        // "same as the other" keeps `_S` for uniform scaling and reserves `_V`
        // for a stretch someone actually asked for.
        let mirrorsY = !animatesY && restingY == 1
        let mirrorsX = !animatesX && restingX == 1
        var times = boundaries(x: animatesX ? x : nil, y: animatesY ? y : nil, duration: duration)

        // A single key is a value held, not a segment: one command that starts
        // and ends at the same moment says so, and dropping it would lose a
        // scale the clip is meant to keep.
        if times.count == 1 { times.append(times[0]) }
        guard times.count >= 2 else { return [] }

        var commands: [Command] = []
        for (start, end) in zip(times, times.dropFirst()) {
            let rawStartX = animatesX ? x.value(at: start) : restingX
            let rawStartY = animatesY ? y.value(at: start) : restingY
            let rawEndX = animatesX ? x.value(at: end) : restingX
            let rawEndY = animatesY ? y.value(at: end) : restingY

            let startX = mirrorsX ? rawStartY : rawStartX
            let startY = mirrorsY ? rawStartX : rawStartY
            let endX = mirrorsX ? rawEndY : rawEndX
            let endY = mirrorsY ? rawEndX : rawEndY

            // The easing belongs to the key the segment leaves, as everywhere
            // else. With both axes animating, the one that owns this boundary
            // supplies it.
            let easingX: Easing? = animatesX
                ? x.keyframes.first { $0.time == start }?.easing : nil
            let easingY: Easing? = animatesY
                ? y.keyframes.first { $0.time == start }?.easing : nil
            let easing: Easing = easingX ?? easingY ?? .linear

            // A segment that holds the default on both axes says nothing.
            if startX == 1, startY == 1, endX == 1, endY == 1 { continue }

            commands.append(Command(
                easing: easing, startTime: start, endTime: end,
                payload: startX == startY && endX == endY
                    ? .scale(start: startX, end: endX)
                    : .vectorScale(startX: startX, startY: startY, endX: endX, endY: endY),
            ))
        }
        return commands
    }

    /// Every moment either axis names, so no key falls inside a segment.
    private static func boundaries(
        x: KeyframeTrack?,
        y: KeyframeTrack?,
        duration: Double,
    ) -> [Double] {
        var times = Set<Double>()
        for track in [x, y].compactMap({ $0 }) {
            for keyframe in track.keyframes { times.insert(keyframe.time) }
        }
        guard !times.isEmpty else { return [] }
        return times.sorted()
    }

    private static func propertyCommands(
        _ transform: Transform,
        _ property: TransformProperty,
        duration: Double,
        payload: (Double, Double) -> Command.Payload,
    ) -> [Command] {
        // A switched-off animation is not animation: the property falls back to
        // its resting value, the same as if it had no keys at all.
        let track = transform[property]

        guard track.isActive else {
            let resting = transform[value: property]
            guard resting != property.defaultValue else { return [] }
            return [Command(
                easing: .linear, startTime: 0, endTime: 0,
                payload: payload(resting, resting),
            )]
        }

        return simpleCommands(
            track,
            duration: duration,
            defaultValue: property.defaultValue,
            payload: payload,
        )
    }

    // ─── Position ────────────────────────────────────────────────────────────

    private static func positionCommands(_ transform: Transform, duration: Double) -> [Command] {
        let x = transform[.x]
        let y = transform[.y]

        // Neither animated — or both switched off: the sprite's own default
        // position already says where it is, so nothing needs writing.
        if !x.isAnimated, !y.isAnimated { return [] }

        // One axis only — `_MX` and `_MY` exist for exactly this, and cost half
        // of what an `_M` repeating a constant would.
        if x.isAnimated, !y.isAnimated {
            return simpleCommands(
                x, duration: duration,
                defaultValue: TransformProperty.x.defaultValue,
                payload: { .moveX(start: $0, end: $1) },
            )
        }
        if y.isAnimated, !x.isAnimated {
            return simpleCommands(
                y, duration: duration,
                defaultValue: TransformProperty.y.defaultValue,
                payload: { .moveY(start: $0, end: $1) },
            )
        }

        // Both animated. `_M` takes a pair, so the segments are cut at every
        // keyframe of either axis: a key on one axis has to become a command
        // boundary, or its curve is lost inside a segment the other axis
        // defined.
        var times = Set(x.keyframes.map(\.time))
        times.formUnion(y.keyframes.map(\.time))
        let boundaries = times.sorted()

        return zip(boundaries, boundaries.dropFirst()).map { from, to in
            // The easing of whichever axis has a key here; falling back to the
            // other keeps a segment that only one axis started from going
            // linear by accident.
            let easing = x.keyframes.first { abs($0.time - from) < 0.5 }?.easing
                ?? y.keyframes.first { abs($0.time - from) < 0.5 }?.easing
                ?? .linear

            return Command(
                easing: easing,
                startTime: from,
                endTime: to,
                payload: .move(
                    startX: x.value(at: from), startY: y.value(at: from),
                    endX: x.value(at: to), endY: y.value(at: to),
                ),
            )
        }
    }

    // ─── One-value properties ────────────────────────────────────────────────

    /// Commands for a track whose property takes a single number.
    private static func simpleCommands(
        _ track: KeyframeTrack,
        duration: Double,
        defaultValue: Double,
        payload: (Double, Double) -> Command.Payload,
    ) -> [Command] {
        guard let first = track.first else { return [] }

        // A single keyframe is a held value. Written as a zero-length command
        // at its own time, which is how a storyboard states a constant — and
        // skipped when it says nothing the default does not already say.
        guard track.isAnimated else {
            guard first.value != defaultValue else { return [] }
            return [Command(
                easing: .linear,
                startTime: first.time,
                endTime: first.time,
                payload: payload(first.value, first.value),
            )]
        }

        return track.segments.map { segment in
            Command(
                easing: segment.from.easing,
                startTime: segment.from.time,
                endTime: segment.to.time,
                payload: payload(segment.from.value, segment.to.value),
            )
        }
    }
}
