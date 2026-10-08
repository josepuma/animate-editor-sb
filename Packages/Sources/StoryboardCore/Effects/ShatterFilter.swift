import Foundation

/// Breaks each sprite into a grid of pieces that fly apart.
///
/// Every piece is a derived image the size of the original with only its own
/// cell left in it, so up to the break the pieces sit exactly on top of one
/// another and draw the sprite whole — no seam, and no need to know how big
/// the image is, which Core cannot. At `Break At` each piece takes over its
/// own path outward from the middle, turning and fading.
///
/// The cost is a sprite per piece, named in the multiplier, and atlas memory:
/// a piece is a whole canvas, mostly empty.
public struct ShatterFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let columns = "columns"
        public static let rows = "rows"
        public static let breakAt = "breakAt"
        public static let fly = "fly"
        public static let distance = "distance"
        public static let spin = "spin"
        public static let gravity = "gravity"
    }

    public static let descriptor = FilterDescriptor(
        type: "shatter",
        name: "Shatter",
        category: .destroy,
        systemImage: "square.grid.3x3.middle.filled",
        parameters: [
            EffectParameter(id: Param.columns, name: "Columns", group: "Shatter", defaultValue: .integer(4), range: 1...10, step: 1),
            EffectParameter(id: Param.rows, name: "Rows", group: "Shatter", defaultValue: .integer(3), range: 1...10, step: 1),
            EffectParameter(id: Param.breakAt, name: "Break At", group: "Shatter", defaultValue: .number(1000), range: 0...60000, step: 10, unit: "ms"),
            EffectParameter(id: Param.fly, name: "Fly", group: "Shatter", defaultValue: .number(900), range: 50...10000, step: 10, unit: "ms"),
            EffectParameter(id: Param.distance, name: "Distance", group: "Shatter", defaultValue: .number(140), range: 0...1000, step: 5, unit: "px"),
            EffectParameter(id: Param.spin, name: "Spin", group: "Shatter", defaultValue: .number(120), range: 0...1080, step: 5, unit: "°"),
            EffectParameter(id: Param.gravity, name: "Gravity", group: "Shatter", defaultValue: .number(400), range: -2000...2000, step: 10, unit: "px/s²"),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        Double(max(1, context.integer(Param.columns)) * max(1, context.integer(Param.rows)))
    }

    public func duration(of clipDuration: Double, in context: FilterContext) -> Double {
        max(clipDuration, context.number(Param.breakAt) + context.number(Param.fly))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let columns = min(max(1, context.integer(Param.columns)), DerivedSprite.tileRange.upperBound)
        let rows = min(max(1, context.integer(Param.rows)), DerivedSprite.tileRange.upperBound)
        guard columns * rows > 1 else { return sprites }
        let settings = Settings(
            at: context.number(Param.breakAt), fly: max(1, context.number(Param.fly)),
            distance: context.number(Param.distance), spin: context.number(Param.spin) * .pi / 180,
            gravity: context.number(Param.gravity),
        )
        let root = FilterParticles.stream(context)

        return sprites.enumerated().flatMap { index, sprite -> [StoryboardSprite] in
            guard sprite.loops.isEmpty, let prepared = StoryboardResolver.prepare([sprite]).first,
                  prepared.activeStart < settings.at, prepared.activeEnd > settings.at
            else { return [sprite] }
            var stream = root.stream(index)
            return (0..<(columns * rows)).map { cell in
                piece(
                    of: sprite, prepared: prepared, id: "\(context.idPrefix)/s\(index)/\(cell)",
                    cell: cell, columns: columns, rows: rows, settings: settings, rng: &stream,
                )
            }
        }
    }

    /// The part of `command` before `time`, ending on the value it has there.
    ///
    /// Linear rather than its own curve: a curve cut short is not the same
    /// curve over a shorter span. Every piece is cut the same way, so they
    /// still assemble exactly.
    static func truncated(_ command: Command, at time: Double) -> Command {
        let progress = applyEasing(command.easing, (time - command.startTime) / (command.endTime - command.startTime))
        let lerp = { (a: Double, b: Double) in a + (b - a) * progress }
        let payload: Command.Payload = switch command.payload {
        case let .move(sx, sy, ex, ey): .move(startX: sx, startY: sy, endX: lerp(sx, ex), endY: lerp(sy, ey))
        case let .moveX(s, e): .moveX(start: s, end: lerp(s, e))
        case let .moveY(s, e): .moveY(start: s, end: lerp(s, e))
        case let .rotate(s, e): .rotate(start: s, end: lerp(s, e))
        case let .fade(s, e): .fade(start: s, end: lerp(s, e))
        default: command.payload
        }
        return Command(easing: .linear, startTime: command.startTime, endTime: time, payload: payload)
    }

    private struct Settings {
        var at: Double
        var fly: Double
        var distance: Double
        var spin: Double
        var gravity: Double
    }

    private func piece(
        of sprite: StoryboardSprite, prepared: PreparedSprite, id: String,
        cell: Int, columns: Int, rows: Int, settings: Settings, rng: inout EffectRandom,
    ) -> StoryboardSprite {
        var piece = sprite
        piece.id = id
        piece.filePath = DerivedSprite.tiled(sprite.filePath, columns: columns, rows: rows, index: cell)

        // Up to the break the piece is the sprite; after it, where it is, how
        // it turns and how it fades are the shatter's.
        // Cut by hand: `AnimatedFactor` leaves a command it does not rewrite
        // whole, so a fade spanning the break would run on beside the
        // piece's own and the two would fight.
        let owned: (Command) -> Bool = { $0.isPosition || $0.kind == .rotate || $0.kind == .fade }
        piece.commands = sprite.commands.compactMap { command in
            guard owned(command), command.endTime > settings.at else { return command }
            guard command.startTime < settings.at else { return nil }
            return Self.truncated(command, at: settings.at)
        }

        let state = StoryboardResolver.state(of: prepared, at: settings.at)
        // Outward from the middle of the image: (−0.5…0.5) per axis, turned
        // and scaled with the sprite, so a rotated sprite breaks along itself.
        let u = (Double(cell % columns) + 0.5) / Double(columns) - 0.5
        let v = (Double(cell / columns) + 0.5) / Double(rows) - 0.5
        let push = settings.distance * 2 * (0.7 + 0.6 * rng.unit())
        let local = (x: u * push * (state.scaleX < 0 ? -1 : 1), y: v * push * (state.scaleY < 0 ? -1 : 1))
        let turn = state.rotation
        let velocity = (
            x: (local.x * cos(turn) - local.y * sin(turn)) / (settings.fly / 1000),
            y: (local.x * sin(turn) + local.y * cos(turn)) / (settings.fly / 1000),
        )
        let seconds = settings.fly / 1000
        func position(_ fraction: Double) -> (x: Double, y: Double) {
            let t = seconds * fraction
            return (state.x + velocity.x * t, state.y + velocity.y * t + 0.5 * settings.gravity * t * t)
        }
        let end = settings.at + settings.fly
        let segments = settings.gravity == 0 ? 1 : 4
        for segment in 0..<segments {
            let from = position(Double(segment) / Double(segments))
            let to = position(Double(segment + 1) / Double(segments))
            piece.commands.append(Command(
                easing: .linear,
                startTime: settings.at + settings.fly * Double(segment) / Double(segments),
                endTime: settings.at + settings.fly * Double(segment + 1) / Double(segments),
                payload: .move(startX: from.x, startY: from.y, endX: to.x, endY: to.y),
            ))
        }
        piece.commands.append(Command(
            easing: .quadOut, startTime: settings.at, endTime: end,
            payload: .rotate(start: turn, end: turn + rng.symmetric(settings.spin)),
        ))
        piece.commands.append(Command(
            easing: .quadIn, startTime: settings.at, endTime: end,
            payload: .fade(start: state.opacity, end: 0),
        ))
        return piece
    }
}
