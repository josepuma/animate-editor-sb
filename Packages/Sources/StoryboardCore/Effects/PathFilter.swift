import Foundation

/// Carries the source of an effect along a curve.
///
/// The one thing a clip's transform cannot do. A transform moves the finished
/// result — particles and all — so dragging it takes the whole cloud with it
/// and the arrangement never changes. This moves only where each sprite is
/// **born**: what has already been emitted stays where it came out, and the
/// trail forms behind the source on its own.
///
/// That is the difference between waving a lit sparkler and sliding a
/// photograph of one.
///
/// `Follow` is the other reading, for things that travel far: each sprite runs
/// the curve itself over its own life. Emit Along on Chevron March loses the
/// path the instant a chevron is out — it flies 800px to the right on its own
/// velocity — and a march along a curve is exactly what the effect is for.
///
/// Filed under Motion rather than Stylise because it is not a look: Glow and
/// Chromatic change how something appears, this changes where it happens.
public struct PathFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let path = "path"
        public static let ease = "ease"
        public static let alignToPath = "alignToPath"
        public static let loops = "loops"
        public static let mode = "mode"
    }

    /// What the path moves: where each sprite is born, or the sprite itself.
    public enum Mode: String, CaseIterable, Sendable {
        /// The source travels; what it emits keeps its own motion.
        case emitAlong = "Emit Along"
        /// Every sprite travels the whole curve over its own life.
        case follow = "Follow"
    }

    public static let descriptor = FilterDescriptor(
        type: "path",
        name: "Motion Path",
        category: .motion,
        systemImage: "scribble.variable",
        parameters: [
            EffectParameter(
                id: Param.path,
                name: "Path",
                group: "Path",
                defaultValue: .path(MotionPath()),
            ),
            // Emit Along by default: filters land in finished projects, and a
            // default that changed the output would rewrite approved work.
            EffectParameter(
                id: Param.mode,
                name: "Mode",
                group: "Path",
                defaultValue: .choice(Mode.emitAlong.rawValue),
                options: Mode.allCases.map(\.rawValue),
            ),
            // How the source paces itself along the curve.
            //
            // Separate from `Ease`, which curves the commands a sprite already
            // has: this is how fast the *source* travels, and a comet that
            // starts slowly and tears away is a different thing from one whose
            // sparks each accelerate.
            EffectParameter(
                id: Param.ease,
                name: "Pacing",
                group: "Path",
                defaultValue: .choice(Pacing.steady.rawValue),
                options: Pacing.allCases.map(\.rawValue),
            ),
            // Whether what is emitted leans the way the source is heading.
            //
            // Off by default: a spark has no front, and rotating a round
            // particle does nothing but write a command per sprite. On, a
            // streak or a flame lies along the curve.
            EffectParameter(
                id: Param.alignToPath,
                name: "Face Along Path",
                group: "Path",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.loops,
                name: "Laps",
                group: "Path",
                defaultValue: .number(1),
                range: 0.1...8,
                step: 0.1,
                unit: "×",
            ),
        ],
    )

    /// How the source paces itself along the curve.
    public enum Pacing: String, CaseIterable, Sendable {
        case steady = "Steady"
        case accelerate = "Accelerate"
        case settle = "Settle"
        case ease = "Ease In Out"

        func progress(_ t: Double) -> Double {
            switch self {
            case .steady: t
            case .accelerate: t * t
            case .settle: 1 - (1 - t) * (1 - t)
            case .ease: t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
            }
        }
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let path = context.path(Param.path)
        guard !path.isEmpty else { return sprites }

        let pacing = Pacing(rawValue: context.choice(Param.ease)) ?? .steady
        let aligns = context.toggle(Param.alignToPath)
        let laps = max(0.1, context.number(Param.loops))

        if Mode(rawValue: context.choice(Param.mode)) == .follow {
            return follow(sprites, along: path, pacing: pacing, aligns: aligns, laps: laps, prefix: context.idPrefix)
        }

        // The clip's own span, so every sprite is placed against the same
        // journey. Measured from the sprites rather than taken from the clip
        // because a filter is handed output, not the node that made it.
        let birthTimes = sprites.compactMap { $0.commands.map(\.startTime).min() }
        guard let first = birthTimes.min(), let last = birthTimes.max() else {
            return sprites
        }

        // A burst has nothing to spread by time — everything leaves at once, so
        // every sprite would ask the path for the same point and land in a
        // heap. Spread by **index** instead: the burst becomes a row of sparks
        // laid along the curve, which is an effect there was no other way to
        // get.
        //
        // Detected rather than declared. A parameter would make the author
        // classify their own emitter before the filter would work, and the
        // answer is already in the sprites.
        let isInstant = last - first < 1

        // Where the effect sits before the path takes it over.
        //
        // Measured from the sprites rather than assumed to be the stage centre.
        // A filter runs **after** the clip's transform, so an effect placed at
        // y: 360 arrives already there — and a displacement worked out from the
        // centre would then be added on top of that, landing the whole thing
        // twice as far from the middle as the path says. The path is where the
        // source goes, not how far it moves.
        let originX = sprites.map(\.defaultX).reduce(0, +) / Double(max(1, sprites.count))
        let originY = sprites.map(\.defaultY).reduce(0, +) / Double(max(1, sprites.count))

        return sprites.enumerated().map { index, sprite in
            let birth = sprite.commands.map(\.startTime).min() ?? first

            // Where the source was when this sprite came out — which is the
            // whole idea. Sampling at the *current* time instead would drag
            // every particle along the curve behind the source, and the trail
            // would collapse back into a moving cloud.
            let elapsed = isInstant
                ? Double(index) / Double(max(1, sprites.count - 1))
                : (birth - first) / (last - first)
            let t = (pacing.progress(elapsed) * laps).truncatingRemainder(dividingBy: 1.0000001)

            guard let at = path.position(at: t) else { return sprite }

            let dx = at.x - originX
            let dy = at.y - originY

            var moved = sprite
            moved.id = "\(context.idPrefix)/p\(index)"
            moved.defaultX += dx
            moved.defaultY += dy
            moved.commands = sprite.commands.map { command in
                shift(command, dx: dx, dy: dy)
            }

            if aligns {
                let facing = Self.facing(path, at: t)
                moved.commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth,
                    payload: .rotate(start: facing, end: facing),
                ))
            }

            return moved
        }
    }

    // ─── Follow ──────────────────────────────────────────────────────────────

    /// Moves per lap. `_M` is a straight line, so a curve is a row of chords;
    /// measured on an arch, twelve keep a sprite within a pixel of the curve,
    /// and a path of many points gets more so every segment keeps its bend.
    private static func segmentsPerLap(_ path: MotionPath) -> Int {
        min(48, max(16, 8 * (path.points.count - 1)))
    }

    /// Every sprite runs the curve over its own life.
    ///
    /// The sprite's own movement is replaced, not added to: two `_M` commands
    /// over the same time fight rather than sum, and a chevron's 420px/s to the
    /// right is exactly what pulled it off the path. What it keeps is where it
    /// was born relative to the effect's origin, so an emitter with an area —
    /// a ring, a bar — carries its shape along the curve instead of collapsing
    /// onto a line.
    private func follow(
        _ sprites: [StoryboardSprite],
        along path: MotionPath,
        pacing: Pacing,
        aligns: Bool,
        laps: Double,
        prefix: String,
    ) -> [StoryboardSprite] {
        let births = sprites.map(Self.birthPosition)
        let originX = births.map(\.x).reduce(0, +) / Double(max(1, births.count))
        let originY = births.map(\.y).reduce(0, +) / Double(max(1, births.count))
        let steps = Self.segmentsPerLap(path) * Int(laps.rounded(.up))

        return sprites.enumerated().map { index, sprite in
            let birth = sprite.commands.map(\.startTime).min()
            let death = sprite.commands.map(\.endTime).max()
            guard let birth, let death, death > birth else { return sprite }

            let dx = births[index].x - originX
            let dy = births[index].y - originY
            let place = { (at: Double) -> (x: Double, y: Double) in
                let point = Self.position(path, at: at)
                return (point.x + dx, point.y + dy)
            }
            let time = { (fraction: Double) in birth + (death - birth) * fraction }

            // How far along the course, in laps, at a fraction of the life.
            let course = { (fraction: Double) in pacing.progress(fraction) * laps }

            var moved = sprite
            moved.id = "\(prefix)/p\(index)"
            let start = place(0)
            moved.defaultX = start.x
            moved.defaultY = start.y
            moved.commands = sprite.commands.filter { command in
                switch command.payload {
                case .move, .moveX, .moveY: false
                case .rotate: !aligns
                default: true
                }
            }

            var facing = aligns ? Self.facing(path, at: 0) : 0

            for step in 0 ..< steps {
                let from = Double(step) / Double(steps)
                let to = Double(step + 1) / Double(steps)
                let a = course(from)
                let b = course(to)
                let lapA = floor(a)
                // An end landing exactly on a whole lap belongs to the lap
                // that just finished, so its position is the path's end.
                let lapB = max(lapA, ceil(b) - 1)

                // A lap turning over inside this step: finish at the path's
                // end, jump back to its start, carry on. Interpolating straight
                // across would sweep the sprite back over the whole path.
                var pieces: [(from: Double, to: Double, a: Double, b: Double)] = []
                if lapB > lapA, b > a {
                    let turn = from + (to - from) * (lapB - a) / (b - a)
                    pieces = [(from, turn, a - lapA, 1), (turn, to, 0, b - lapB)]
                } else {
                    pieces = [(from, to, a - lapA, b - lapA)]
                }

                for piece in pieces {
                    let p0 = place(piece.a)
                    let p1 = place(piece.b)
                    moved.commands.append(Command(
                        easing: .linear,
                        startTime: time(piece.from),
                        endTime: time(piece.to),
                        payload: .move(startX: p0.x, startY: p0.y, endX: p1.x, endY: p1.y),
                    ))

                    guard aligns else { continue }
                    let start = Self.nearest(Self.facing(path, at: piece.a), to: facing)
                    let end = Self.nearest(Self.facing(path, at: piece.b), to: start)
                    facing = end
                    moved.commands.append(Command(
                        easing: .linear,
                        startTime: time(piece.from),
                        endTime: time(piece.to),
                        payload: .rotate(start: start, end: end),
                    ))
                }
            }

            return moved
        }
    }

    /// Where a sprite was the moment it came out.
    private static func birthPosition(_ sprite: StoryboardSprite) -> (x: Double, y: Double) {
        var x = sprite.defaultX
        var y = sprite.defaultY
        var xAt = Double.infinity
        var yAt = Double.infinity
        for command in sprite.commands {
            switch command.payload {
            case let .move(startX, startY, _, _):
                if command.startTime < xAt { x = startX; xAt = command.startTime }
                if command.startTime < yAt { y = startY; yAt = command.startTime }
            case let .moveX(start, _):
                if command.startTime < xAt { x = start; xAt = command.startTime }
            case let .moveY(start, _):
                if command.startTime < yAt { y = start; yAt = command.startTime }
            default:
                break
            }
        }
        return (x, y)
    }

    private static func position(_ path: MotionPath, at t: Double) -> (x: Double, y: Double) {
        path.position(at: t) ?? (0, 0)
    }

    /// The rotation that turns a sprite's up toward where the path is heading.
    ///
    /// Up is (0, −1), and the shader turns it to (sin r, −cos r) in a y-down
    /// space; asking that to equal the heading (cos a, sin a) gives r = a + π/2.
    /// Writing the heading alone — what this filter used to do — laid every
    /// up-pointing sprite across the curve instead of along it. The same
    /// derivation `Align to Motion` already had to be corrected to.
    static func facing(_ path: MotionPath, at t: Double) -> Double {
        path.heading(at: t) * .pi / 180 + .pi / 2
    }

    /// `angle` moved by whole turns to sit nearest `reference`, so a rotation
    /// crossing ±π turns the short way instead of spinning round.
    private static func nearest(_ angle: Double, to reference: Double) -> Double {
        angle - (2 * .pi) * ((angle - reference) / (2 * .pi)).rounded()
    }

    private func shift(_ command: Command, dx: Double, dy: Double) -> Command {
        var moved = command
        switch command.payload {
        case let .move(startX, startY, endX, endY):
            moved.payload = .move(
                startX: startX + dx, startY: startY + dy,
                endX: endX + dx, endY: endY + dy,
            )
        case let .moveX(start, end):
            moved.payload = .moveX(start: start + dx, end: end + dx)
        case let .moveY(start, end):
            moved.payload = .moveY(start: start + dy, end: end + dy)
        default:
            break
        }
        return moved
    }
}
