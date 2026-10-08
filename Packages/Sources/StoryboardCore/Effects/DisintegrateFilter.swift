import Foundation

/// Each sprite comes apart into motes over the end of its life.
///
/// The glyph particles' Disintegrate, for any clip: an image, a shape, an
/// emitter's particles. The motes leave from anywhere inside an area around
/// the sprite — Core cannot open an image to know its size, so the area is a
/// number the author sets, scaled with the sprite.
public struct DisintegrateFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let window = "window"
        public static let width = "areaWidth"
        public static let height = "areaHeight"
        public static let direction = "direction"
    }

    public static let descriptor = FilterDescriptor(
        type: "disintegrate",
        name: "Disintegrate",
        category: .destroy,
        systemImage: "aqi.medium",
        parameters: [
            EffectParameter(
                id: Param.window, name: "Over Last", group: "Disintegrate",
                defaultValue: .number(500), range: 50...10000, step: 10, unit: "ms",
            ),
            EffectParameter(id: Param.width, name: "Area Width", group: "Disintegrate", defaultValue: .number(40), range: 0...1000, step: 1, unit: "px"),
            EffectParameter(id: Param.height, name: "Area Height", group: "Disintegrate", defaultValue: .number(40), range: 0...1000, step: 1, unit: "px"),
            // The emitter's convention: 270 is up, because screen y grows down.
            EffectParameter(id: Param.direction, name: "Direction", group: "Disintegrate", defaultValue: .number(270), range: 0...360, step: 5, unit: "°"),
        ] + FilterParticles.parameters(group: "Particles", count: 12, speed: 60, spread: 120, sprite: "Dust"),
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        1 + Double(min(Int(context.number(FilterParticles.Param.count).rounded()), FilterParticles.maximumPerSprite))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let count = FilterParticles.perSprite(context, sprites: sprites.count)
        guard count > 0 else { return sprites }
        let window = context.number(Param.window)
        let half = (x: context.number(Param.width) / 2, y: context.number(Param.height) / 2)
        let burst = FilterParticles.burst(context, direction: context.number(Param.direction))
        let path = FilterParticles.image(context).path
        let root = FilterParticles.stream(context)

        let motes = sprites.enumerated().flatMap { index, sprite -> [StoryboardSprite] in
            guard let prepared = StoryboardResolver.prepare([sprite]).first, prepared.activeStart.isFinite
            else { return [] }
            let death = prepared.activeEnd
            let start = max(prepared.activeStart, death - window)
            guard death > start else { return [] }
            var stream = root.stream(index)
            return (0..<count).map { k in
                // Evenly along the window by index: a sorted draw bunches.
                let at = start + (death - start) * (Double(k) + 0.5) / Double(count)
                let state = StoryboardResolver.state(of: prepared, at: at)
                let origin = (
                    x: state.x + stream.symmetric(half.x * abs(state.scaleX)),
                    y: state.y + stream.symmetric(half.y * abs(state.scaleY)),
                )
                return burst.particle(id: "\(context.idPrefix)/d\(index)/\(k)", path: path, origin: origin, at: at, rng: &stream)
            }
        }
        return sprites + motes
    }
}
