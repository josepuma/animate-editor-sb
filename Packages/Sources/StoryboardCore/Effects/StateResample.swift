import Foundation

/// Rewrites where a sprite is, how big, how opaque and which way it faces, as
/// a function of what it already was — the machinery behind the 3D filters.
///
/// Faking depth touches several properties at once: a card turning narrows
/// and flips, a sprite going round a cylinder moves, shrinks, dims and shows
/// its back. Each is read with the resolver that draws the sprite and written
/// back as linear chains that **replace** the sprite's own position, scale,
/// opacity and flips, so nothing it had is left beside them to fight.
///
/// The trade every resample makes: an eased command becomes straight chords
/// between the given times. Callers put a time on every original command's
/// ends, so a linear clip comes out exact.
enum StateResample {
    struct Frame {
        var x: Double
        var y: Double
        var scaleX: Double
        var scaleY: Double
        var opacity: Double
        var flipH: Bool
        var flipV: Bool
    }

    /// The sprite's own life and every command boundary: the times a caller
    /// starts from before adding its own.
    static func boundaries(of sprite: StoryboardSprite) -> [Double] {
        sprite.commands.flatMap { [$0.startTime, $0.endTime] }
    }

    /// Whether a sprite's loops touch anything this rewrites. A loop body
    /// keeps writing its own values on every pass, against whatever is
    /// written here, so such a sprite is left alone.
    static func isLooped(_ sprite: StoryboardSprite) -> Bool {
        sprite.loops.contains { loop in loop.commands.contains { rewritten($0) } }
    }

    static func rewrite(
        _ sprite: StoryboardSprite,
        at times: [Double],
        _ transform: (Frame, Double) -> Frame,
    ) -> StoryboardSprite {
        guard !isLooped(sprite), let prepared = StoryboardResolver.prepare([sprite]).first,
              prepared.activeStart.isFinite
        else { return sprite }

        let birth = prepared.activeStart
        let death = prepared.activeEnd
        let points = Array(Set(times.filter { $0 >= birth && $0 <= death } + [birth, death])).sorted()

        // A local function, not a stored closure: it captures `transform`,
        // which is non-escaping.
        func frame(_ time: Double) -> Frame {
            let state = StoryboardResolver.state(of: prepared, at: time)
            return transform(Frame(
                x: state.x, y: state.y, scaleX: state.scaleX, scaleY: state.scaleY,
                opacity: state.opacity, flipH: state.flipH, flipV: state.flipV,
            ), time)
        }
        let frames = points.map { frame($0) }

        var result = sprite
        result.commands.removeAll(where: rewritten)
        result.defaultX = frames[0].x
        result.defaultY = frames[0].y

        guard points.count > 1 else {
            result.commands.append(Command(easing: .linear, startTime: birth, endTime: birth, payload: .vectorScale(
                startX: frames[0].scaleX, startY: frames[0].scaleY, endX: frames[0].scaleX, endY: frames[0].scaleY,
            )))
            return result
        }

        for index in 1..<points.count {
            let (a, b) = (frames[index - 1], frames[index])
            let (from, to) = (points[index - 1], points[index])
            result.commands.append(Command(easing: .linear, startTime: from, endTime: to, payload: .move(
                startX: a.x, startY: a.y, endX: b.x, endY: b.y,
            )))
            result.commands.append(Command(easing: .linear, startTime: from, endTime: to, payload: .vectorScale(
                startX: a.scaleX, startY: a.scaleY, endX: b.scaleX, endY: b.scaleY,
            )))
            result.commands.append(Command(easing: .linear, startTime: from, endTime: to, payload: .fade(
                start: a.opacity, end: b.opacity,
            )))
        }

        // A flip holds over a span; which way an interval faces is read at
        // its middle, so callers put a time on every crossing.
        for (kind, faces) in [(ParameterKind.flipHorizontal, \Frame.flipH), (.flipVertical, \Frame.flipV)] {
            var runStart: Double?
            for index in 1..<points.count {
                let middle = frame((points[index - 1] + points[index]) / 2)
                if middle[keyPath: faces] {
                    runStart = runStart ?? points[index - 1]
                } else if let start = runStart {
                    result.commands.append(Command(easing: .linear, startTime: start, endTime: points[index - 1], payload: .parameter(kind)))
                    runStart = nil
                }
            }
            if let start = runStart {
                result.commands.append(Command(easing: .linear, startTime: start, endTime: death, payload: .parameter(kind)))
            }
        }
        return result
    }

    private static func rewritten(_ command: Command) -> Bool {
        switch command.payload {
        case .move, .moveX, .moveY, .scale, .vectorScale, .fade: true
        case .parameter(.flipHorizontal), .parameter(.flipVertical): true
        default: false
        }
    }
}
