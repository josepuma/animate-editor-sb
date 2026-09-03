import Foundation

/// Repeats a clip across rows and columns.
///
/// The counterpart to ``RadialFilter``: that one arranges copies around a
/// circle, this one lays them out on a lattice. Between them almost every
/// repeating pattern is a couple of parameters rather than a new effect —
/// tiles, curtains, rain, a wall of falling text, a field of drifting motes.
///
/// **A filter and not an effect**, because "repeat this" needs something to
/// repeat. As an effect it could only ever tile whatever sprite it shipped
/// with; as a filter it tiles the image, the text, the emitter — whatever is
/// already on the track.
///
/// The cost is the steepest in the library and it is multiplicative: a 5×5
/// grid over a two-hundred particle emitter is five thousand sprites. The
/// multiplier says so before the file is written.
public struct GridFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let columns = "columns"
        public static let rows = "rows"
        public static let spacingX = "spacingX"
        public static let spacingY = "spacingY"
        public static let stagger = "stagger"
        public static let delay = "delay"
        public static let anchor = "anchor"
        public static let orbits = "orbits"
    }

    /// Where the lattice grows from.
    ///
    /// A grid anchored at the clip is what a duplicate tool does — the original
    /// stays put and copies march away from it. Centred, the clip ends up in
    /// the middle of its own pattern, which is what a wall or a curtain wants:
    /// asked for a screen of tiles, nobody means "and put the first one in the
    /// corner".
    public enum Anchor: String, CaseIterable, Sendable {
        case clip = "From Clip"
        case centred = "Centred"
    }

    public static let descriptor = FilterDescriptor(
        type: "grid",
        name: "Grid",
        category: .stylise,
        systemImage: "square.grid.3x3",
        parameters: [
            EffectParameter(
                id: Param.columns,
                name: "Columns",
                group: "Grid",
                defaultValue: .integer(3),
                range: 1...20,
                step: 1,
            ),
            EffectParameter(
                id: Param.rows,
                name: "Rows",
                group: "Grid",
                defaultValue: .integer(3),
                range: 1...20,
                step: 1,
            ),
            EffectParameter(
                id: Param.spacingX,
                name: "Spacing X",
                group: "Grid",
                defaultValue: .number(120),
                range: 0...854,
                step: 5,
                unit: "px",
            ),
            EffectParameter(
                id: Param.spacingY,
                name: "Spacing Y",
                group: "Grid",
                defaultValue: .number(120),
                range: 0...480,
                step: 5,
                unit: "px",
            ),
            EffectParameter(
                id: Param.anchor,
                name: "Anchor",
                group: "Grid",
                defaultValue: .choice(Anchor.centred.rawValue),
                options: Anchor.allCases.map(\.rawValue),
            ),
            // Whether the lattice turns as one object or each cell turns in
            // place.
            //
            // Off, a rotation on the clip spins every tile where it stands —
            // a mosaic of pinwheels. On, the cells orbit the middle of the
            // grid and the whole pattern turns like one thing.
            //
            // The distinction only exists because osu! has no nested sprites:
            // there is no group to turn, so orbiting has to be baked into each
            // copy's own path. It costs nothing extra — those commands are
            // written either way.
            EffectParameter(
                id: Param.orbits,
                name: "Rotate as Group",
                group: "Grid",
                defaultValue: .toggle(false),
            ),
            // Every cell starting at once is a wall that appears; cells that
            // arrive one after another is a wave crossing the screen.
            //
            // This is what stops a grid reading as wallpaper. A tiled logo that
            // all lands together is one big object; the same tiles landing in
            // sequence read as many, which is the whole reason to have made
            // copies.
            EffectParameter(
                id: Param.delay,
                name: "Cell Delay",
                group: "Sequence",
                defaultValue: .number(0),
                range: 0...500,
                step: 10,
                unit: "ms",
            ),
            EffectParameter(
                id: Param.stagger,
                name: "Order",
                group: "Sequence",
                defaultValue: .choice(Stagger.rows.rawValue),
                options: Stagger.allCases.map(\.rawValue),
            ),
        ],
    )

    /// The direction the delay sweeps in.
    ///
    /// Four orders rather than one, because the sweep *is* the effect once
    /// there is a delay: reading order is a typewriter, diagonal is a wipe, and
    /// outward is something detonating in the middle.
    public enum Stagger: String, CaseIterable, Sendable {
        case rows = "Row by Row"
        case columns = "Column by Column"
        case diagonal = "Diagonal"
        case outward = "From Centre"
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        Double(max(1, context.integer(Param.columns)) * max(1, context.integer(Param.rows)))
    }

    /// A staggered grid runs past its clip: the last cell starts after every
    /// one before it, and still has its whole life to live.
    public func duration(of clipDuration: Double, in context: FilterContext) -> Double {
        let delay = max(0, context.number(Param.delay))
        guard delay > 0 else { return clipDuration }

        let columns = max(1, context.integer(Param.columns))
        let rows = max(1, context.integer(Param.rows))
        let stagger = Stagger(rawValue: context.choice(Param.stagger)) ?? .rows

        var last = 0.0
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                last = max(last, Self.order(
                    row: row, column: column,
                    rows: rows, columns: columns,
                    by: stagger,
                ) * delay)
            }
        }
        return clipDuration + last
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let columns = max(1, context.integer(Param.columns))
        let rows = max(1, context.integer(Param.rows))
        let spacingX = context.number(Param.spacingX)
        let spacingY = context.number(Param.spacingY)
        let delay = max(0, context.number(Param.delay))
        let stagger = Stagger(rawValue: context.choice(Param.stagger)) ?? .rows
        let anchor = Anchor(rawValue: context.choice(Param.anchor)) ?? .centred
        let orbits = context.toggle(Param.orbits)

        // One cell is no grid, and a grid with no spacing stacks every copy on
        // top of the original: sprites paid for and never seen.
        guard columns * rows > 1, spacingX > 0 || spacingY > 0 else { return sprites }

        // Centred, the lattice is pulled back by half its own extent so the
        // clip sits in the middle of it rather than at its corner.
        let originX = anchor == .centred ? -Double(columns - 1) * spacingX / 2 : 0
        let originY = anchor == .centred ? -Double(rows - 1) * spacingY / 2 : 0

        var result: [StoryboardSprite] = []
        result.reserveCapacity(sprites.count * columns * rows)

        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let dx = originX + Double(column) * spacingX
                let dy = originY + Double(row) * spacingY
                let offset = delay * Self.order(
                    row: row, column: column,
                    rows: rows, columns: columns,
                    by: stagger,
                )

                for (index, sprite) in sprites.enumerated() {
                    // The cell the clip itself occupies is the clip, untouched
                    // — unless the lattice moved it, which centring does.
                    let isOrigin = row == 0 && column == 0
                    guard !isOrigin || dx != 0 || dy != 0 || offset != 0 else {
                        result.append(sprite)
                        continue
                    }

                    var copy = sprite
                    if !isOrigin {
                        copy.id = "\(context.idPrefix)/g\(row)-\(column)-\(index)"
                    }
                    // The pivot the cell orbits: the middle of the lattice,
                    // which is wherever the clip sits once the anchor has had
                    // its say.
                    let pivotX = sprite.defaultX + (anchor == .centred ? 0 : -originX)
                    let pivotY = sprite.defaultY + (anchor == .centred ? 0 : -originY)

                    if orbits {
                        // Turned about the pivot by however much the clip is
                        // rotated at that moment — read from the commands,
                        // because a filter never sees the transform that wrote
                        // them. The same trick the wiggle uses to find where a
                        // sprite is.
                        let born = sprite.commands.map(\.startTime).min() ?? 0
                        let turn = Self.rotation(of: context.transform, at: born)
                        let placed = Self.orbit(dx: dx, dy: dy, by: turn)
                        copy.defaultX += placed.x
                        copy.defaultY += placed.y
                    } else {
                        copy.defaultX += dx
                        copy.defaultY += dy
                    }

                    copy.commands = orbits
                        ? Self.orbitedCommands(
                            of: sprite,
                            offsetX: dx, offsetY: dy,
                            pivotX: pivotX, pivotY: pivotY,
                            transform: context.transform,
                        )
                        : sprite.commands.map { command in
                            var moved = command
                            moved.payload = Self.shift(command.payload, dx: dx, dy: dy)
                            return moved
                        }

                    // The delay moves the whole cell in time, so a copy plays
                    // exactly what the original does, later — rather than being
                    // sampled somewhere in the middle of it.
                    if offset != 0 {
                        copy.commands = copy.commands.map { command in
                            var moved = command
                            moved.timing.startTime += offset
                            moved.timing.endTime += offset
                            return moved
                        }
                    }
                    // A loop body is relative to its own iteration, so only the
                    // start moves — the same rule the evaluator follows when it
                    // shifts a clip onto the timeline.
                    copy.loops = sprite.loops.map { loop in
                        var moved = loop
                        moved.startTime += offset
                        moved.commands = loop.commands.map { command in
                            var shifted = command
                            shifted.payload = orbits
                                ? Self.orbited(
                                    command,
                                    offsetX: dx, offsetY: dy,
                                    pivotX: pivotX, pivotY: pivotY,
                                    transform: context.transform,
                                )
                                : Self.shift(command.payload, dx: dx, dy: dy)
                            return shifted
                        }
                        return moved
                    }

                    result.append(copy)
                }
            }
        }

        return result
    }

    /// How many delays into the sequence a cell sits.
    private static func order(
        row: Int,
        column: Int,
        rows: Int,
        columns: Int,
        by stagger: Stagger,
    ) -> Double {
        switch stagger {
        case .rows:
            Double(row * columns + column)
        case .columns:
            Double(column * rows + row)
        case .diagonal:
            Double(row + column)
        case .outward:
            // Distance from the middle, so the wave leaves the centre rather
            // than sweeping across — which is what an impact looks like.
            (
                pow(Double(row) - Double(rows - 1) / 2, 2)
                    + pow(Double(column) - Double(columns - 1) / 2, 2)
            ).squareRoot()
        }
    }

    /// A cell's offset from the pivot, turned by an angle.
    private static func orbit(dx: Double, dy: Double, by angle: Double) -> (x: Double, y: Double) {
        (
            x: dx * cos(angle) - dy * sin(angle),
            y: dx * sin(angle) + dy * cos(angle)
        )
    }

    /// How far the *group* has turned at a moment, in radians.
    ///
    /// Taken from the clip's transform rather than from the sprites' `_R`
    /// commands, and that distinction is the whole of a bug worth remembering:
    /// **a sprite's rotation is not the group's.** An emitter gives every
    /// particle its own tilt — random spread, or `Align to Motion` — so a
    /// filter reading the commands sees a clip spinning wildly when nothing is
    /// animated at all. Measured on a fire preset with 180° of spread, the
    /// lattice collapsed from cells 100px apart to cells 11px apart, each
    /// orbiting its own random angle.
    ///
    /// Degrees in, radians out: the transform stores degrees and converts when
    /// it writes a command, so a reader has to convert too.
    private static func rotation(of transform: Transform, at time: Double) -> Double {
        transform.value(.rotation, at: time) * .pi / 180
    }

    /// The most a chord may fall short of the arc it cuts across, in pixels.
    ///
    /// `_M` interpolates in straight lines, so an orbit is really a polygon —
    /// and how far its corners cut inside the true circle grows with the
    /// radius. Eight segments read as a smooth circle at the pivot and as a
    /// visible bounce a hundred pixels out: measured, 7.6px of sag per corner,
    /// eight times a turn.
    ///
    /// A pixel and a half, not the half-pixel that geometry would ask for.
    /// Precision here is paid for in **every frame** — each segment is a
    /// command the resolver walks — and the cost lands on the widest cells,
    /// which are also the most numerous. Measured on an 8×6 grid over a
    /// 48-particle emitter: half a pixel bought 49,160 commands and dropped the
    /// editor to 45fps; a pixel and a half is a third fewer for a wobble
    /// nobody can point at. And it is still five times finer than the bounce
    /// that started this.
    private static let arcTolerance: Double = 1.5

    /// The most segments one orbit is worth cutting into.
    ///
    /// Every segment is a line in the file, multiplied by every cell in the
    /// grid — so a wide lattice cannot be allowed to spend without limit. Past
    /// this the sag is well under a pixel anyway.
    /// Past this the sag is well under the tolerance anyway, and every
    /// segment is a command the resolver walks on every frame.
    private static let maximumArcSegments = 48

    /// A cell's whole orbit, cut finely enough for the radius it sits at.
    ///
    /// This is where the finer cut belongs rather than in `GroupTransform`: a
    /// clip is transformed *before* any filter has copied it, so at that point
    /// there is one sprite sitting on the pivot at radius zero. The distance
    /// that makes a chord sag is created here, so the correction is too.
    private static func orbitedCommands(
        of sprite: StoryboardSprite,
        offsetX: Double,
        offsetY: Double,
        pivotX: Double,
        pivotY: Double,
        transform: Transform,
    ) -> [Command] {
        // How far the sprite actually orbits, not how far its cell sits.
        //
        // A cell's offset is where the *clip* was copied to; the sprite inside
        // it travels on top of that. An emitter throwing particles 300px out of
        // a cell 500px from the pivot is orbiting at 800, and buying the
        // segments for 500 leaves the sag it was meant to remove — measured,
        // 6.5px against a 1.5px tolerance.
        let reach = sprite.commands.reduce(0.0) { widest, command in
            switch command.payload {
            case let .move(startX, startY, endX, endY):
                max(widest, hypot(startX - pivotX, startY - pivotY), hypot(endX - pivotX, endY - pivotY))
            case let .moveX(start, end):
                max(widest, abs(start - pivotX), abs(end - pivotX))
            case let .moveY(start, end):
                max(widest, abs(start - pivotY), abs(end - pivotY))
            default:
                widest
            }
        }
        let radius = max(
            (offsetX * offsetX + offsetY * offsetY).squareRoot(),
            hypot(offsetX, offsetY) + reach,
        )

        var result: [Command] = []
        result.reserveCapacity(sprite.commands.count)

        for command in sprite.commands {
            // Only movement bends; everything else rides along untouched.
            guard command.kind == .move || command.kind == .moveX || command.kind == .moveY else {
                result.append(command)
                continue
            }

            let turn = abs(
                rotation(of: transform, at: command.endTime)
                    - rotation(of: transform, at: command.startTime),
            )
            let steps = segments(atRadius: radius, turn: turn)

            guard steps > 1, command.endTime > command.startTime else {
                var moved = command
                moved.payload = orbited(
                    command,
                    offsetX: offsetX, offsetY: offsetY,
                    pivotX: pivotX, pivotY: pivotY,
                    transform: transform,
                )
                result.append(moved)
                continue
            }

            // Cut into steps, each one a chord short enough to stay within
            // tolerance of the arc it replaces.
            let span = command.endTime - command.startTime
            for step in 0 ..< steps {
                let from = command.startTime + span * Double(step) / Double(steps)
                let to = command.startTime + span * Double(step + 1) / Double(steps)

                var piece = command
                piece.timing.startTime = from
                piece.timing.endTime = to
                piece.payload = orbited(
                    sampled(command, from: from, to: to),
                    offsetX: offsetX, offsetY: offsetY,
                    pivotX: pivotX, pivotY: pivotY,
                    transform: transform,
                )
                result.append(piece)
            }
        }

        return result
    }

    /// How finely to cut an orbit so the chords stay within ``arcTolerance``.
    ///
    /// Derived rather than fixed, which is what any tessellator does: a chord's
    /// sag is `r · (1 − cos(θ/2))`, so the count needed follows from the radius
    /// and the tolerance. A cell near the pivot stays cheap; one far out buys
    /// the segments it actually needs.
    private static func segments(atRadius radius: Double, turn: Double) -> Int {
        guard radius > arcTolerance, turn > 0 else { return 1 }

        // How wide one segment may be before its chord sags too far.
        let widest = 2 * acos(max(-1, min(1, 1 - arcTolerance / radius)))
        guard widest > 0 else { return maximumArcSegments }

        return min(maximumArcSegments, max(1, Int((turn / widest).rounded(.up))))
    }

    /// The stretch of a movement command between two moments.
    private static func sampled(_ command: Command, from: Double, to: Double) -> Command {
        let span = command.endTime - command.startTime
        guard span > 0 else { return command }

        let a = (from - command.startTime) / span
        let b = (to - command.startTime) / span
        func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
            start + (end - start) * t
        }

        var piece = command
        piece.timing.startTime = from
        piece.timing.endTime = to
        // Linear, because the piece is a slice of an already-sampled path: the
        // original curve is expressed by where the slices land, not by each
        // slice's own easing.
        piece.timing.easing = .linear

        switch command.payload {
        case let .move(startX, startY, endX, endY):
            piece.payload = .move(
                startX: lerp(startX, endX, a), startY: lerp(startY, endY, a),
                endX: lerp(startX, endX, b), endY: lerp(startY, endY, b),
            )
        case let .moveX(start, end):
            piece.payload = .moveX(start: lerp(start, end, a), end: lerp(start, end, b))
        case let .moveY(start, end):
            piece.payload = .moveY(start: lerp(start, end, a), end: lerp(start, end, b))
        default:
            break
        }
        return piece
    }

    /// A command's coordinates, orbited about the pivot.
    ///
    /// Each end of the command is turned by the rotation at *its own* moment,
    /// so a cell sweeps an arc rather than sliding along the chord: the clip is
    /// turning while the sprite moves, and a straight line through a turning
    /// frame is a curve.
    private static func orbited(
        _ command: Command,
        offsetX: Double,
        offsetY: Double,
        pivotX: Double,
        pivotY: Double,
        transform: Transform,
    ) -> Command.Payload {
        let atStart = orbit(
            dx: offsetX, dy: offsetY,
            by: rotation(of: transform, at: command.startTime),
        )
        let atEnd = orbit(
            dx: offsetX, dy: offsetY,
            by: rotation(of: transform, at: command.endTime),
        )

        switch command.payload {
        case let .move(startX, startY, endX, endY):
            return .move(
                startX: startX + atStart.x, startY: startY + atStart.y,
                endX: endX + atEnd.x, endY: endY + atEnd.y,
            )

        // A single-axis move stops being single-axis once it orbits, so it has
        // to become a full `_M` — kept as `_MX` the cell would slide across the
        // screen instead of around the pivot. The same correction `RadialFilter`
        // makes for the same reason.
        case let .moveX(start, end):
            return .move(
                startX: start + atStart.x, startY: pivotY + atStart.y,
                endX: end + atEnd.x, endY: pivotY + atEnd.y,
            )

        case let .moveY(start, end):
            return .move(
                startX: pivotX + atStart.x, startY: start + atStart.y,
                endX: pivotX + atEnd.x, endY: end + atEnd.y,
            )

        default:
            return command.payload
        }
    }

    /// Moves whatever coordinates a command names.
    ///
    /// Every one of them, not just the sprite's default position: a particle
    /// spends its whole life inside an `_M`, and osu! draws the command rather
    /// than the default — so a cell whose default moved but whose commands did
    /// not snaps back to the original spot the moment it starts.
    private static func shift(_ payload: Command.Payload, dx: Double, dy: Double) -> Command.Payload {
        switch payload {
        case let .move(startX, startY, endX, endY):
            .move(startX: startX + dx, startY: startY + dy, endX: endX + dx, endY: endY + dy)
        case let .moveX(start, end):
            .moveX(start: start + dx, end: end + dx)
        case let .moveY(start, end):
            .moveY(start: start + dy, end: end + dy)
        default:
            payload
        }
    }
}
