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
/// Filed under Motion rather than Stylise because it is not a look: Glow and
/// Chromatic change how something appears, this changes where it happens.
public struct PathFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let path = "path"
        public static let ease = "ease"
        public static let alignToPath = "alignToPath"
        public static let loops = "loops"
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
                let heading = path.heading(at: t) * .pi / 180
                moved.commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth,
                    payload: .rotate(start: heading, end: heading),
                ))
            }

            return moved
        }
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
