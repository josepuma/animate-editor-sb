import Foundation

/// Reading what a sprite's own commands say, at one moment.
///
/// What a filter needs before it can take a property over: a pulse, or a
/// scale following the song, multiplies the size and opacity the sprite
/// already has rather than replacing them — so a sprite drawn at half size
/// kicks from half size, and one fading in keeps fading in. One place for it,
/// because two filters reading the same thing two ways is how they end up
/// disagreeing about the same sprite.
extension StoryboardSprite {
    /// The scale at `time`, per axis.
    ///
    /// Both axes, because a sprite may be stretched — and a filter that read
    /// one number and wrote a uniform `_S` would quietly square it: a 854×100
    /// bar with a beat on it came back as a block.
    func restingScale(at time: Double) -> (x: Double, y: Double) {
        var scale = (x: 1.0, y: 1.0)

        for command in commands {
            guard command.startTime <= time else { continue }
            let span = command.endTime - command.startTime
            let progress = span > 0 ? min(1, (time - command.startTime) / span) : 1

            switch command.payload {
            case let .scale(start, end):
                let value = start + (end - start) * progress
                scale = (value, value)
            case let .vectorScale(startX, startY, endX, endY):
                scale = (
                    startX + (endX - startX) * progress,
                    startY + (endY - startY) * progress,
                )
            default:
                continue
            }
        }

        return scale
    }

    /// The opacity at `time`.
    func restingOpacity(at time: Double) -> Double {
        var opacity = 1.0

        for command in commands {
            guard command.startTime <= time, case let .fade(start, end) = command.payload else { continue }
            let span = command.endTime - command.startTime
            let progress = span > 0 ? min(1, (time - command.startTime) / span) : 1
            opacity = start + (end - start) * progress
        }

        return opacity
    }
}
