import Foundation

/// Every moving sprite sheds sparks along its path — a sub-emitter faked:
/// osu! cannot have a particle emit others, but each spark can be placed
/// where its parent was at that instant, read with the resolver that draws it.
///
/// `Against Motion` throws them back along the way the sprite came, which is
/// what reads as a comet's tail; off, they go where `Direction` says.
public struct SparkTrailFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let againstMotion = "againstMotion"
        public static let direction = "direction"
    }

    public static let descriptor = FilterDescriptor(
        type: "spark-trail",
        name: "Spark Trail",
        category: .destroy,
        systemImage: "sparkles",
        parameters: [
            EffectParameter(id: Param.againstMotion, name: "Against Motion", group: "Spark Trail", defaultValue: .toggle(true)),
            EffectParameter(
                id: Param.direction, name: "Direction", group: "Spark Trail",
                defaultValue: .number(270), range: 0...360, step: 5, unit: "°",
                shownWhen: .init(parameter: Param.againstMotion, isAnyOf: ["false"]),
            ),
        ] + FilterParticles.parameters(group: "Particles", count: 10, speed: 80, spread: 40, sprite: "Spark"),
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        1 + Double(min(Int(context.number(FilterParticles.Param.count).rounded()), FilterParticles.maximumPerSprite))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let count = FilterParticles.perSprite(context, sprites: sprites.count)
        guard count > 0 else { return sprites }
        let against = context.toggle(Param.againstMotion)
        let fixed = context.number(Param.direction)
        let path = FilterParticles.image(context).path
        let root = FilterParticles.stream(context)

        let sparks = sprites.enumerated().flatMap { index, sprite -> [StoryboardSprite] in
            let moves = sprite.commands.filter(\.isPosition)
            guard let start = moves.map(\.startTime).min(), let end = moves.map(\.endTime).max(), end > start,
                  let prepared = StoryboardResolver.prepare([sprite]).first
            else { return [] }
            var stream = root.stream(index)
            return (0..<count).compactMap { k in
                let at = start + (end - start) * (Double(k) + 0.5) / Double(count)
                let here = StoryboardResolver.state(of: prepared, at: at)
                var direction = fixed
                if against {
                    let ahead = StoryboardResolver.state(of: prepared, at: min(end, at + 8))
                    let behind = StoryboardResolver.state(of: prepared, at: max(start, at - 8))
                    let dx = ahead.x - behind.x
                    let dy = ahead.y - behind.y
                    // Standing still at this instant: nothing to trail.
                    guard dx * dx + dy * dy > 1e-9 else { return nil }
                    direction = atan2(dy, dx) * 180 / .pi + 180
                }
                let burst = FilterParticles.burst(context, direction: direction)
                return burst.particle(id: "\(context.idPrefix)/t\(index)/\(k)", path: path, origin: (here.x, here.y), at: at, rng: &stream)
            }
        }
        return sparks + sprites
    }
}
