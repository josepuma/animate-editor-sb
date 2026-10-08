import Foundation

/// Wraps the clip round a turning cylinder: a line of text going round a
/// drum, a ring of cards on a carousel.
///
/// Each sprite's x is read as a distance round the drum — `(x − centre) /
/// radius` radians — so a line wraps by its own layout, and `Spin` turns the
/// drum. From in front, a point on a cylinder is a sine across and a cosine
/// deep: the depth shrinks it with `Perspective`, foreshortens it, dims it
/// with `Back Fade` and mirrors it round the back.
///
/// What it cannot do is reorder: a sprite's draw order is fixed for its life,
/// so a letter passing behind its neighbours still draws over them. Back Fade
/// is what keeps that from reading as wrong.
public struct CarouselFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let x = "x"
        public static let radius = "radius"
        public static let spin = "spin"
        public static let perspective = "perspective"
        public static let backFade = "backFade"
        public static let rate = "rate"
    }

    /// Samples per sprite, at most; past this the steps lengthen.
    static let maximumSteps = 48

    public static let descriptor = FilterDescriptor(
        type: "carousel",
        name: "Carousel",
        category: .threeD,
        systemImage: "cylinder",
        parameters: [
            EffectParameter(id: Param.x, name: "Centre X", group: "Carousel", defaultValue: .number(320), range: -107...747, step: 1, unit: "px"),
            EffectParameter(id: Param.radius, name: "Radius", group: "Carousel", defaultValue: .number(200), range: 10...1000, step: 5, unit: "px"),
            EffectParameter(id: Param.spin, name: "Spin", group: "Carousel", defaultValue: .number(60), range: -720...720, step: 5, unit: "°/s"),
            EffectParameter(
                id: Param.perspective, name: "Perspective", group: "Carousel",
                // How much smaller the back of the drum is than its front.
                defaultValue: .number(0.4), range: 0...0.9, step: 0.05, presentation: .slider,
            ),
            EffectParameter(id: Param.backFade, name: "Back Fade", group: "Carousel", defaultValue: .number(0.7), range: 0...1, step: 0.05, presentation: .slider),
            EffectParameter(id: Param.rate, name: "Sample Rate", group: "Carousel", defaultValue: .number(15), range: 2...30, step: 1, unit: "/s"),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let centre = context.number(Param.x)
        let radius = max(context.number(Param.radius), 1)
        let spin = context.number(Param.spin) * .pi / 180
        let perspective = context.number(Param.perspective)
        let backFade = context.number(Param.backFade)
        let rate = context.number(Param.rate)

        return sprites.map { sprite in
            let ends = sprite.commands.map(\.startTime) + sprite.commands.map(\.endTime)
            guard let birth = ends.min(), let death = ends.max() else { return sprite }
            let span = death - birth
            let steps = min(max(Int((span * rate / 1000).rounded(.up)), 1), Self.maximumSteps)
            let times = (0...steps).map { $0 == steps ? death : birth + span * Double($0) / Double(steps) }

            return StateResample.rewrite(sprite, at: StateResample.boundaries(of: sprite) + times) { frame, time in
                let theta = (frame.x - centre) / radius + spin * time / 1000
                let depth = cos(theta)
                let size = 1 - perspective * (1 - depth) / 2
                var placed = frame
                placed.x = centre + radius * sin(theta)
                placed.scaleX = frame.scaleX * size * abs(depth)
                placed.scaleY = frame.scaleY * size
                placed.opacity = frame.opacity * (1 - backFade * max(0, -depth))
                placed.flipH = frame.flipH != (depth < 0)
                return placed
            }
        }
    }
}
