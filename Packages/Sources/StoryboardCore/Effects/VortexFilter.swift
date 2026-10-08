import Foundation

/// Turns everything on the clip around a point, harder the closer it is.
///
/// `Twist` is a fixed swirl — a field bent into a spiral; `Spin` keeps it
/// turning, so a cloud drains around the centre like water. Only positions
/// turn: osu! cannot bend an image, so each sprite rides the swirl upright.
public struct VortexFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let x = "x"
        public static let y = "y"
        public static let radius = "radius"
        public static let twist = "twist"
        public static let spin = "spin"
        public static let rate = "rate"
    }

    public static let descriptor = FilterDescriptor(
        type: "vortex",
        name: "Vortex",
        category: .motion,
        systemImage: "tornado",
        parameters: [
            EffectParameter(id: Param.x, name: "Centre X", group: "Vortex", defaultValue: .number(320), range: -107...747, step: 1, unit: "px"),
            EffectParameter(id: Param.y, name: "Centre Y", group: "Vortex", defaultValue: .number(240), range: 0...480, step: 1, unit: "px"),
            EffectParameter(id: Param.radius, name: "Radius", group: "Vortex", defaultValue: .number(300), range: 10...1000, step: 5, unit: "px"),
            EffectParameter(id: Param.twist, name: "Twist", group: "Vortex", defaultValue: .number(90), range: -720...720, step: 5, unit: "°"),
            EffectParameter(id: Param.spin, name: "Spin", group: "Vortex", defaultValue: .number(0), range: -720...720, step: 5, unit: "°/s"),
            EffectParameter(id: Param.rate, name: "Sample Rate", group: "Vortex", defaultValue: .number(10), range: 2...30, step: 1, unit: "/s"),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let cx = context.number(Param.x)
        let cy = context.number(Param.y)
        let radius = context.number(Param.radius)
        let twist = context.number(Param.twist)
        let spin = context.number(Param.spin)
        guard twist != 0 || spin != 0 else { return sprites }
        let rate = context.number(Param.rate)

        return sprites.map { sprite in
            PositionResample.warp(sprite, rate: rate) { x, y, time in
                let dx = x - cx
                let dy = y - cy
                let r = (dx * dx + dy * dy).squareRoot()
                guard r < radius else { return (x, y) }
                // Squared falloff: full turn at the centre, easing to nothing
                // at the rim, so the edge of the swirl has no seam.
                let falloff = (1 - r / radius) * (1 - r / radius)
                let angle = (twist + spin * time / 1000) * falloff * .pi / 180
                return (cx + dx * cos(angle) - dy * sin(angle), cy + dx * sin(angle) + dy * cos(angle))
            }
        }
    }
}
