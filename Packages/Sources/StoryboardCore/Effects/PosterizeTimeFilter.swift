import Foundation

/// Plays the clip's movement at a low frame rate: stop-motion, or anime "on
/// twos", over whatever it is applied to.
///
/// Each moving property is sampled with the resolver that draws it on a grid
/// of frames aligned to the clip — so every sprite steps on the same beat —
/// and written as zero-length commands. A zero-length command sets a value and
/// the sprite holds it until the next, which is exactly a held frame.
///
/// Position, size and turn step; opacity and colour do not. A fade stepped at
/// twelve frames a second reads as flicker, not as a choppier fade.
public struct PosterizeTimeFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let fps = "fps"
    }

    /// Frames per property per sprite, at most; past this the frames lengthen.
    public static let maximumFrames = 48

    public static let descriptor = FilterDescriptor(
        type: "posterize-time",
        name: "Posterize Time",
        category: .time,
        systemImage: "film.stack",
        parameters: [
            EffectParameter(
                id: Param.fps, name: "Frame Rate", group: "Posterize Time",
                defaultValue: .number(12), range: 1...30, step: 1, unit: "fps",
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let frame = 1000 / max(context.number(Param.fps), 1)
        return sprites.map { posterized($0, frame: frame) }
    }

    private enum Family: CaseIterable {
        case position, scale, rotation

        var kinds: [CommandKind] {
            switch self {
            case .position: [.move, .moveX, .moveY]
            case .scale: [.scale, .vectorScale]
            case .rotation: [.rotate]
            }
        }
    }

    private func posterized(_ sprite: StoryboardSprite, frame: Double) -> StoryboardSprite {
        guard let prepared = StoryboardResolver.prepare([sprite]).first else { return sprite }
        var result = sprite

        for family in Family.allCases {
            let commands = sprite.commands.filter { family.kinds.contains($0.kind) }
            // Only what moves: a held value is already a frame.
            guard commands.contains(where: { $0.endTime > $0.startTime && !$0.payload.isConstant }),
                  !sprite.loops.contains(where: { $0.commands.contains { family.kinds.contains($0.kind) } }),
                  let first = commands.map(\.startTime).min(),
                  let last = commands.map(\.endTime).max()
            else { continue }

            let times = Self.frames(from: first, to: last, frame: frame)
            let vector = commands.contains { $0.kind == .vectorScale }
            result.commands.removeAll { family.kinds.contains($0.kind) }
            for time in times {
                let state = StoryboardResolver.state(of: prepared, at: time)
                let payload: Command.Payload = switch family {
                case .position: .move(startX: state.x, startY: state.y, endX: state.x, endY: state.y)
                case .scale: vector
                    ? .vectorScale(startX: state.scaleX, startY: state.scaleY, endX: state.scaleX, endY: state.scaleY)
                    : .scale(start: state.scaleX, end: state.scaleX)
                case .rotation: .rotate(start: state.rotation, end: state.rotation)
                }
                result.commands.append(Command(easing: .linear, startTime: time, endTime: time, payload: payload))
            }
        }
        return result
    }

    /// Frame times on a grid from the clip's zero, plus both ends, so the
    /// first value is set at birth and the last one is the one it lands on.
    /// By index, never by adding a step.
    static func frames(from first: Double, to last: Double, frame: Double) -> [Double] {
        let span = last - first
        let count = Int((span / frame).rounded(.up))
        guard count <= maximumFrames else {
            return (0...maximumFrames).map { $0 == maximumFrames ? last : first + span * Double($0) / Double(maximumFrames) }
        }
        let firstIndex = Int((first / frame).rounded(.up))
        var times = [first]
        var index = firstIndex
        while true {
            let time = Double(index) * frame
            guard time < last else { break }
            if time > first { times.append(time) }
            index += 1
        }
        times.append(last)
        return times
    }
}

private extension Command.Payload {
    /// Whether the command holds one value from start to end.
    var isConstant: Bool {
        switch self {
        case let .move(sx, sy, ex, ey), let .vectorScale(sx, sy, ex, ey): sx == ex && sy == ey
        case let .moveX(s, e), let .moveY(s, e), let .scale(s, e), let .rotate(s, e), let .fade(s, e): s == e
        default: true
        }
    }
}
