import Foundation

/// Pulls everything on the clip toward a point, or pushes it away.
///
/// A force field without a simulation: a storyboard cannot integrate forces
/// frame by frame, so the pull is a fraction of the way to the point that
/// grows over `Ramp` — sprites curve in rather than snapping, and a negative
/// strength blows them out.
public struct AttractorFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let x = "x"
        public static let y = "y"
        public static let strength = "strength"
        public static let radius = "radius"
        public static let ramp = "ramp"
        public static let rate = "rate"
    }

    public static let descriptor = FilterDescriptor(
        type: "attractor",
        name: "Attractor",
        category: .motion,
        systemImage: "scope",
        parameters: [
            EffectParameter(id: Param.x, name: "Point X", group: "Attractor", defaultValue: .number(320), range: -107...747, step: 1, unit: "px"),
            EffectParameter(id: Param.y, name: "Point Y", group: "Attractor", defaultValue: .number(240), range: 0...480, step: 1, unit: "px"),
            EffectParameter(
                id: Param.strength, name: "Strength", group: "Attractor",
                // 1 lands everything in range on the point; below zero repels.
                defaultValue: .number(0.5), range: -1...1, step: 0.05, presentation: .slider,
            ),
            EffectParameter(id: Param.radius, name: "Radius", group: "Attractor", defaultValue: .number(400), range: 10...1500, step: 10, unit: "px"),
            EffectParameter(id: Param.ramp, name: "Ramp", group: "Attractor", defaultValue: .number(1000), range: 0...10000, step: 50, unit: "ms"),
            EffectParameter(id: Param.rate, name: "Sample Rate", group: "Attractor", defaultValue: .number(10), range: 2...30, step: 1, unit: "/s"),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let px = context.number(Param.x)
        let py = context.number(Param.y)
        let strength = context.number(Param.strength)
        guard strength != 0 else { return sprites }
        let radius = context.number(Param.radius)
        let ramp = context.number(Param.ramp)
        let rate = context.number(Param.rate)

        return sprites.map { sprite in
            PositionResample.warp(sprite, rate: rate) { x, y, time in
                let dx = px - x
                let dy = py - y
                let r = (dx * dx + dy * dy).squareRoot()
                guard r < radius else { return (x, y) }
                // Smoothstep over the ramp, against clip time: the field
                // switches on once for the whole clip, not per sprite.
                let t = ramp > 0 ? min(max(time / ramp, 0), 1) : 1
                let pull = strength * (1 - r / radius) * t * t * (3 - 2 * t)
                return (x + dx * pull, y + dy * pull)
            }
        }
    }
}
