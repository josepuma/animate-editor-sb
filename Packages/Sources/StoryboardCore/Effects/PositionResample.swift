import Foundation

/// Rewrites where a sprite is, as a function of where it already was.
///
/// Turbulence, Vortex and Attractor all move a sprite by an amount that
/// depends on its position *and* on time — a curve no single `_M` can carry.
/// So each samples the sprite with the resolver that draws it, warps every
/// sample, and writes the result back as a chain of straight moves that
/// **replaces** the sprite's own: osu! does not add two moves, it lets the
/// last one win, so a warp written beside the original would tug against it.
///
/// The cost is the trade every resampled path makes: an eased move becomes
/// straight chords between samples. `rate` decides how many, capped so a long
/// life lengthens its steps rather than writing thousands of commands.
enum PositionResample {
    /// Moves per sprite, at most. Past this the steps lengthen — never cut,
    /// since a cut leaves the rest of the life holding one position.
    static let maximumSteps = 48

    /// - Parameter warp: the new position for a sampled one, at a local time.
    static func warp(
        _ sprite: StoryboardSprite,
        rate: Double,
        _ warp: (_ x: Double, _ y: Double, _ time: Double) -> (x: Double, y: Double),
    ) -> StoryboardSprite {
        // A loop body that moves the sprite would keep writing its own
        // positions on every pass, against whatever is written here.
        guard !sprite.loops.contains(where: { $0.commands.contains(where: \.isPosition) }),
              let prepared = StoryboardResolver.prepare([sprite]).first
        else { return sprite }

        let birth = prepared.activeStart
        let death = prepared.activeEnd
        guard birth.isFinite, death.isFinite else { return sprite }

        let span = max(death - birth, 0)
        let steps = min(max(Int((span * rate / 1000).rounded(.up)), 1), maximumSteps)
        // By index, never by adding a step: an accumulated step drifts and two
        // moves overlap by a hair.
        let times = span > 0
            ? (0...steps).map { $0 == steps ? death : birth + span * Double($0) / Double(steps) }
            : [birth]
        let points = times.map { time in
            let state = StoryboardResolver.state(of: prepared, at: time)
            return warp(state.x, state.y, time)
        }

        var warped = sprite
        warped.commands.removeAll(where: \.isPosition)
        warped.defaultX = points[0].x
        warped.defaultY = points[0].y

        let moves = points.contains { abs($0.x - points[0].x) > 1e-9 || abs($0.y - points[0].y) > 1e-9 }
        guard moves else { return warped }

        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            warped.commands.append(Command(
                easing: .linear, startTime: times[index - 1], endTime: times[index],
                payload: .move(startX: from.x, startY: from.y, endX: to.x, endY: to.y),
            ))
        }
        return warped
    }
}

extension Command {
    var isPosition: Bool {
        switch kind {
        case .move, .moveX, .moveY: true
        default: false
        }
    }
}
