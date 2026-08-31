import Foundation

/// Applies a clip's transform to everything it produced, as one object.
///
/// The clip moves, turns and scales as a whole — its sprites keep their
/// relative arrangement, the way a group does in any editor. That is what a
/// transform means to someone looking at a clip: not "where the emitter is",
/// but "where this thing is".
///
/// ## Why it is not free
///
/// osu! has no nested sprites, so there is no group to move — every sprite has
/// to be moved individually, and a rotation has to be baked into each one's
/// path. A straight line through a turning frame is a curve, and a curve costs
/// several commands where the line cost one.
///
/// The alternative, moving only the point particles are born from, costs
/// nothing at all but is a different effect: sparks off a moving torch rather
/// than a firework carried across the screen. This is the one people mean.
public enum GroupTransform {
    /// How many segments a rotated path is cut into.
    ///
    /// A rotation turns straight motion into an arc, and `_M` interpolates in
    /// straight lines. Eight is where the bend stops reading as a hinge —
    /// the same figure the emitter uses for gravity, and for the same reason.
    private static let arcSegments = 8

    /// Applies `transform` to `sprites` over a clip of `duration`.
    ///
    /// - Returns: the sprites as the transform leaves them. When nothing is
    ///   animated and nothing is offset, they come back untouched — a clip that
    ///   sits still should cost exactly what it did before transforms existed.
    public static func apply(
        _ transform: Transform,
        to sprites: [StoryboardSprite],
        duration: Double,
    ) -> [StoryboardSprite] {
        let movesX = transform[.x].isActive
        let movesY = transform[.y].isActive
        let rotates = transform.isSet(.rotation)
        let scales = transform.isSet(.scale)
        let fades = transform.isSet(.opacity)

        guard movesX || movesY || rotates || scales || fades else { return sprites }

        // The origin the group turns and scales around: the centre of where its
        // sprites sit. Rotating about the canvas centre instead would swing a
        // clip placed off to one side across the whole screen.
        let pivot = centre(of: sprites)

        return sprites.map { sprite in
            transformed(
                sprite,
                transform: transform,
                pivot: pivot,
                duration: duration,
                rotates: rotates,
                scales: scales,
                fades: fades,
                moves: movesX || movesY,
            )
        }
    }

    /// Roughly how many commands a transform adds per sprite.
    ///
    /// Reported so the editor can say what an animated clip will cost before a
    /// file is written, the way it already does for filters.
    public static func estimatedCommandsPerSprite(_ transform: Transform) -> Int {
        var commands = 0
        if transform[.rotation].isActive {
            // A rotation curves every path, so each one is cut into segments.
            commands += arcSegments
        } else if transform[.x].isActive || transform[.y].isActive {
            commands += max(1, transform[.x].keyframes.count + transform[.y].keyframes.count - 1)
        }
        if transform[.scale].isActive { commands += 1 }
        if transform[.opacity].isActive { commands += 1 }
        return commands
    }

    // ─── One sprite ──────────────────────────────────────────────────────────

    private static func transformed(
        _ sprite: StoryboardSprite,
        transform: Transform,
        pivot: (x: Double, y: Double),
        duration: Double,
        rotates: Bool,
        scales: Bool,
        fades: Bool,
        moves: Bool,
    ) -> StoryboardSprite {
        var result = sprite

        // The sprite's own place in the group, which is what gets carried
        // around the pivot.
        let offsetX = sprite.defaultX - pivot.x
        let offsetY = sprite.defaultY - pivot.y

        let isAnimated = transform[.x].isActive
            || transform[.y].isActive
            || transform[.rotation].isActive
            || transform[.scale].isActive

        if isAnimated {
            result.commands = rebuiltMotion(
                sprite,
                transform: transform,
                pivot: pivot,
                offset: (offsetX, offsetY),
                duration: duration,
            )
        } else {
            // Nothing animates: a single placement is enough, and the sprite's
            // own commands carry on untouched.
            let placed = place(
                offset: (offsetX, offsetY),
                pivot: pivot,
                transform: transform,
                at: 0,
            )
            result.defaultX = placed.x
            result.defaultY = placed.y

            let groupScale = transform.value(.scale, at: 0)
            result.commands = sprite.commands.map { scaled($0, by: groupScale) }

            // A sprite with no scale command of its own draws at 1, so scaling
            // by multiplying its commands reaches nothing — the group's scale
            // has to be stated outright.
            if groupScale != 1,
               !sprite.commands.contains(where: { $0.kind == .scale || $0.kind == .vectorScale })
            {
                let start = sprite.commands.map(\.startTime).min() ?? 0
                result.commands.append(Command(
                    easing: .linear, startTime: start, endTime: start,
                    payload: .scale(start: groupScale, end: groupScale),
                ))
            }
        }

        if fades {
            if transform[.opacity].isActive {
                // Animated: the group's own fade, as commands.
                //
                // Multiplying the sprite's fades by the group's value at one
                // instant would be wrong in both directions — a group fading in
                // from zero multiplied everything by zero and the clip vanished
                // entirely.
                result.commands.removeAll { $0.kind == .fade }
                result.commands.append(contentsOf: TransformCommands.build(
                    from: Transform(tracks: ["opacity": transform[.opacity]]),
                    duration: duration,
                ))
            } else {
                let opacity = transform.value(.opacity, at: 0)
                if opacity != 1 {
                    result.commands = result.commands.map { faded($0, by: opacity) }
                }
            }
        }

        if rotates, !transform[.rotation].isActive {
            // A constant turn: added once rather than baked into the path.
            let angle = transform.value(.rotation, at: 0) * .pi / 180
            if angle != 0 {
                result.commands.append(Command(
                    easing: .linear, startTime: 0, endTime: 0,
                    payload: .rotate(start: angle, end: angle),
                ))
            }
        }

        return result
    }

    /// Rebuilds a sprite's motion so it follows the group.
    ///
    /// The sprite's own path is sampled at each step and then carried through
    /// the group's transform at that moment — which is what makes the whole
    /// clip read as one object rather than as sprites that happen to move.
    private static func rebuiltMotion(
        _ sprite: StoryboardSprite,
        transform: Transform,
        pivot: (x: Double, y: Double),
        offset: (x: Double, y: Double),
        duration: Double,
    ) -> [Command] {
        // The sprite's own life, since a transform outside it is meaningless:
        // a particle that ends at two seconds is not carried by a rotation
        // running to ten.
        let birth = sprite.commands.map(\.startTime).min() ?? 0
        let death = sprite.commands.map(\.endTime).max() ?? duration
        let span = max(death - birth, 1)

        // A rotation curves every path; a plain translation does not, so it
        // needs no more segments than its own keyframes.
        // Boundaries at every key of either axis, so each segment is exactly
        // one keyframe span and can carry that key's curve. A rotation bends
        // the path between keys as well, so there the arc is sampled instead.
        let boundaries: [Double] = {
            guard !transform[.rotation].isActive else {
                return (0...arcSegments).map {
                    birth + span * Double($0) / Double(arcSegments)
                }
            }
            var times = Set(transform[.x].keyframes.map(\.time))
            times.formUnion(transform[.y].keyframes.map(\.time))
            times.formUnion([birth, death])
            return times.filter { $0 >= birth && $0 <= death }.sorted()
        }()

        var commands = sprite.commands.filter { $0.kind != .move && $0.kind != .moveX && $0.kind != .moveY }

        // An animated scale needs commands of its own.
        //
        // Folding it in as a factor takes its value at one instant and holds it
        // — the sprite came out frozen at whatever the scale happened to be
        // when it was born, while the inspector showed the value moving. That
        // is the same mistake the opacity path made.
        if transform[.scale].isActive {
            commands.removeAll { $0.kind == .scale || $0.kind == .vectorScale }
            commands.append(contentsOf: TransformCommands.build(
                from: Transform(tracks: ["scale": transform[.scale]]),
                duration: duration,
            ))
        } else {
            let groupScale = transform.value(.scale, at: birth)
            if groupScale != 1 {
                commands = commands.map { scaled($0, by: groupScale) }
                if !sprite.commands.contains(where: { $0.kind == .scale || $0.kind == .vectorScale }) {
                    commands.append(Command(
                        easing: .linear, startTime: birth, endTime: birth,
                        payload: .scale(start: groupScale, end: groupScale),
                    ))
                }
            }
        }

        var previous = position(
            of: sprite, at: birth,
            transform: transform, pivot: pivot, offset: offset,
        )

        for (from, to) in zip(boundaries, boundaries.dropFirst()) {
            let next = position(
                of: sprite, at: to,
                transform: transform, pivot: pivot, offset: offset,
            )

            commands.append(Command(
                // The keyframe's own curve when a segment *is* the segment
                // between two keys, and linear when it is one slice of a
                // sampled arc.
                //
                // Sampling a curve and then writing every piece as linear
                // throws the curve away: with one segment — a plain move, no
                // rotation to bend it — the whole easing vanished and an ease
                // out came through as a straight line.
                easing: transform[.rotation].isActive ? .linear : easing(of: transform, at: from),
                startTime: from,
                endTime: to,
                payload: .move(startX: previous.x, startY: previous.y, endX: next.x, endY: next.y),
            ))
            previous = next
        }

        // The group's own turn, on top of whatever the sprite was already
        // doing: a particle spinning inside a rotating clip does both.
        if transform[.rotation].isActive {
            let start = transform.value(.rotation, at: birth) * .pi / 180
            let end = transform.value(.rotation, at: death) * .pi / 180
            if start != end {
                commands.append(Command(
                    easing: .linear, startTime: birth, endTime: death,
                    payload: .rotate(start: start, end: end),
                ))
            }
        }

        return commands
    }

    /// The curve leaving whichever key governs `time`.
    ///
    /// Position is two tracks and a command carries one easing, so X wins where
    /// both have a key: they are almost always set together, and a disagreement
    /// has to resolve somehow.
    private static func easing(of transform: Transform, at time: Double) -> Easing {
        let onX = transform[.x].keyframes.last { $0.time <= time + 0.5 }
        let onY = transform[.y].keyframes.last { $0.time <= time + 0.5 }
        return onX?.easing ?? onY?.easing ?? .linear
    }

    /// Where a sprite is at `time`, once the group has had its way with it.
    ///
    /// The sprite's own motion is read from its move commands, then carried
    /// through the group's transform — which is what makes the clip read as one
    /// object rather than as sprites that happen to move together.
    private static func position(
        of sprite: StoryboardSprite,
        at time: Double,
        transform: Transform,
        pivot: (x: Double, y: Double),
        offset: (x: Double, y: Double),
    ) -> (x: Double, y: Double) {
        let own = ownPosition(of: sprite, at: time)
        return place(
            offset: (own.x - pivot.x, own.y - pivot.y),
            pivot: pivot,
            transform: transform,
            at: time,
        )
    }

    /// A sprite's position from its own commands, ignoring the group.
    private static func ownPosition(
        of sprite: StoryboardSprite,
        at time: Double,
    ) -> (x: Double, y: Double) {
        var x = sprite.defaultX
        var y = sprite.defaultY

        // The same rule the resolver follows: the most recently started command
        // active at this moment wins, and a finished one holds its end value.
        for command in sprite.commands.sorted(by: { $0.startTime < $1.startTime }) {
            guard command.startTime <= time else { break }
            let progress = command.endTime > command.startTime
                ? min(1, (time - command.startTime) / (command.endTime - command.startTime))
                : 1

            switch command.payload {
            case let .move(sx, sy, ex, ey):
                x = easedLerp(sx, ex, progress, command.easing)
                y = easedLerp(sy, ey, progress, command.easing)
            case let .moveX(start, end):
                x = easedLerp(start, end, progress, command.easing)
            case let .moveY(start, end):
                y = easedLerp(start, end, progress, command.easing)
            default:
                break
            }
        }

        return (x, y)
    }

    /// Where a sprite sits once the group's transform is applied at `time`.
    private static func place(
        offset: (x: Double, y: Double),
        pivot: (x: Double, y: Double),
        transform: Transform,
        at time: Double,
    ) -> (x: Double, y: Double) {
        let scale = transform.value(.scale, at: time)
        let angle = transform.value(.rotation, at: time) * .pi / 180

        // Scaled first, then turned: scaling after a rotation would stretch
        // along the rotated axes and skew the group.
        let scaledX = offset.x * scale
        let scaledY = offset.y * scale

        let turnedX = scaledX * cos(angle) - scaledY * sin(angle)
        let turnedY = scaledX * sin(angle) + scaledY * cos(angle)

        // The group's own displacement, which is its position less where it
        // rests: a clip that has not been moved should not shift its sprites.
        let shiftX = transform.value(.x, at: time) - TransformProperty.x.defaultValue
        let shiftY = transform.value(.y, at: time) - TransformProperty.y.defaultValue

        return (pivot.x + turnedX + shiftX, pivot.y + turnedY + shiftY)
    }

    private static func centre(of sprites: [StoryboardSprite]) -> (x: Double, y: Double) {
        guard !sprites.isEmpty else { return (0, 0) }
        let x = sprites.reduce(0.0) { $0 + $1.defaultX } / Double(sprites.count)
        let y = sprites.reduce(0.0) { $0 + $1.defaultY } / Double(sprites.count)
        return (x, y)
    }

    private static func scaled(_ command: Command, by factor: Double) -> Command {
        guard factor != 1 else { return command }
        switch command.payload {
        case let .scale(start, end):
            return Command(timing: command.timing, payload: .scale(start: start * factor, end: end * factor))
        case let .vectorScale(sx, sy, ex, ey):
            return Command(
                timing: command.timing,
                payload: .vectorScale(startX: sx * factor, startY: sy * factor, endX: ex * factor, endY: ey * factor),
            )
        default:
            return command
        }
    }

    private static func faded(_ command: Command, by factor: Double) -> Command {
        guard case let .fade(start, end) = command.payload else { return command }
        return Command(timing: command.timing, payload: .fade(start: start * factor, end: end * factor))
    }
}
