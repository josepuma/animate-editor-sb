import Foundation

extension StoryboardSprite {
    /// The sprite drawn at `factor` of its size, every scale command
    /// multiplied — loops included — or one held from birth if it had none.
    ///
    /// What pairs with a texture drawn `1 / factor` times larger: the image
    /// shows at the same size on screen with that many more pixels behind it.
    func scaled(by factor: Double) -> StoryboardSprite {
        guard factor != 1 else { return self }
        func scaled(_ command: Command) -> Command {
            switch command.payload {
            case let .scale(start, end):
                Command(timing: command.timing, payload: .scale(start: start * factor, end: end * factor))
            case let .vectorScale(sx, sy, ex, ey):
                Command(timing: command.timing, payload: .vectorScale(
                    startX: sx * factor, startY: sy * factor, endX: ex * factor, endY: ey * factor,
                ))
            default:
                command
            }
        }
        var result = self
        result.commands = commands.map(scaled)
        result.loops = loops.map { loop in
            var looped = loop
            looped.commands = loop.commands.map(scaled)
            return looped
        }
        let sized = (commands + loops.flatMap(\.commands)).contains { $0.kind == .scale || $0.kind == .vectorScale }
        if !sized {
            // Held from the first command on: before it a sprite takes that
            // command's opening value, so one held there covers its whole life.
            let birth = commands.map(\.startTime).min() ?? 0
            result.commands.append(Command(
                easing: .linear, startTime: birth, endTime: birth, payload: .scale(start: factor, end: factor),
            ))
        }
        return result
    }
}
