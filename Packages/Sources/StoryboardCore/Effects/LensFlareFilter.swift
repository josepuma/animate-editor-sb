import Foundation

/// The ghosts a bright light throws through a lens: discs and rings strung on
/// the line from the light through the middle of the frame, swinging the
/// other way as the light moves.
///
/// Every element is an additive sprite placed by the resolver reading the
/// light where it is — so it follows a keyed sun, a script, a particle — and
/// fades with it.
///
/// **The frame's middle is the stage's, before the camera.** Filters run
/// before the storyboard camera is baked, so under a moving camera the line
/// pivots on the stage's centre, not on what ends up in the middle of the
/// picture. With the camera at rest the two are the same.
public struct LensFlareFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let elements = "elements"
        public static let size = "size"
        public static let reach = "reach"
        public static let intensity = "intensity"
        public static let colour = "colour"
        public static let rate = "rate"
    }

    /// Elements for the whole clip. A flare is for a light or two; on an
    /// emitter every particle would string its own, so the per-sprite count
    /// gives way.
    public static let maximumElements = 120

    /// Moves per element, at most; past this the steps lengthen.
    static let maximumSteps = 48

    public static let descriptor = FilterDescriptor(
        type: "lens-flare",
        name: "Lens Flare",
        category: .light,
        systemImage: "camera.aperture",
        parameters: [
            EffectParameter(id: Param.elements, name: "Elements", group: "Lens Flare", defaultValue: .integer(5), range: 2...10, step: 1),
            EffectParameter(id: Param.size, name: "Size", group: "Lens Flare", defaultValue: .number(70), range: 4...600, step: 1, unit: "px"),
            EffectParameter(
                id: Param.reach, name: "Reach", group: "Lens Flare",
                // How far along the line the last ghost lands: 1 is the
                // centre, 2 the light's mirror across it.
                defaultValue: .number(1.8), range: 0.2...3, step: 0.05,
            ),
            EffectParameter(id: Param.intensity, name: "Intensity", group: "Lens Flare", defaultValue: .number(0.5), range: 0...1, step: 0.05, presentation: .slider),
            EffectParameter(id: Param.colour, name: "Colour", group: "Lens Flare", defaultValue: .color(EffectColor(r: 255, g: 210, b: 150))),
            EffectParameter(id: Param.rate, name: "Sample Rate", group: "Lens Flare", defaultValue: .number(15), range: 2...30, step: 1, unit: "/s"),
        ],
    )

    /// What each ghost looks like, cycled: a size against `Size`, an image
    /// and the width it is drawn at, and its share of the intensity. Varied
    /// on purpose — identical discs on a line read as a dotted rule.
    private static let looks: [(size: Double, path: String, source: Double, opacity: Double, warmth: Double)] = [
        (1.0, BuiltInSprite.glow, 64, 1.0, 1.0),
        (0.35, BuiltInSprite.soft, 64, 0.8, 0.6),
        (0.6, BuiltInSprite.hoop(thickness: 0.06), 512, 0.6, 0.3),
        (0.25, BuiltInSprite.soft, 64, 0.9, 0.8),
        (0.9, BuiltInSprite.glow, 64, 0.5, 0.2),
        (0.45, BuiltInSprite.hoop(thickness: 0.12), 512, 0.5, 0.5),
    ]

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        1 + Double(max(2, context.integer(Param.elements)))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let intensity = context.number(Param.intensity)
        guard intensity > 0, !sprites.isEmpty else { return sprites }
        let wanted = max(2, context.integer(Param.elements))
        let count = min(wanted, Self.maximumElements / sprites.count)
        guard count > 0 else { return sprites }
        let size = context.number(Param.size)
        let reach = context.number(Param.reach)
        let colour = context.color(Param.colour)
        let rate = context.number(Param.rate)
        let centre = (x: StageSnap.Stage.centreX, y: StageSnap.Stage.centreY)

        let ghosts = sprites.enumerated().flatMap { index, sprite -> [StoryboardSprite] in
            guard let prepared = StoryboardResolver.prepare([sprite]).first, prepared.activeStart.isFinite
            else { return [] }
            let birth = prepared.activeStart
            let death = prepared.activeEnd
            let span = max(death - birth, 0)
            let steps = min(max(Int((span * rate / 1000).rounded(.up)), 1), Self.maximumSteps)
            // By index, never by adding a step.
            let times = (0...steps).map { $0 == steps ? death : birth + span * Double($0) / Double(steps) }
            let states = times.map { StoryboardResolver.state(of: prepared, at: $0) }

            return (0..<count).map { k in
                let look = Self.looks[k % Self.looks.count]
                let along = reach * Double(k) / Double(count - 1)
                let place = { (state: SpriteRenderState) in
                    (x: state.x + (centre.x - state.x) * along, y: state.y + (centre.y - state.y) * along)
                }
                let first = place(states[0])
                var ghost = StoryboardSprite(
                    id: "\(context.idPrefix)/l\(index)/\(k)", layer: sprite.layer, origin: .centre,
                    filePath: look.path, defaultX: first.x, defaultY: first.y,
                )
                let strength = intensity * look.opacity
                // Warmer near the light, cooler down the line.
                let tint = EffectColor(
                    r: colour.r, g: colour.g * (0.7 + 0.3 * look.warmth), b: colour.b * (0.6 + 0.4 * (1 - look.warmth)),
                )
                for step in times.indices.dropFirst() {
                    let a = place(states[step - 1])
                    let b = place(states[step])
                    ghost.commands.append(Command(easing: .linear, startTime: times[step - 1], endTime: times[step], payload: .move(
                        startX: a.x, startY: a.y, endX: b.x, endY: b.y,
                    )))
                    ghost.commands.append(Command(easing: .linear, startTime: times[step - 1], endTime: times[step], payload: .fade(
                        start: states[step - 1].opacity * strength, end: states[step].opacity * strength,
                    )))
                }
                let scale = size * look.size / look.source
                ghost.commands.append(Command(easing: .linear, startTime: birth, endTime: birth, payload: .scale(start: scale, end: scale)))
                ghost.commands.append(Command(easing: .linear, startTime: birth, endTime: birth, payload: .color(
                    startR: tint.r, startG: tint.g, startB: tint.b, endR: tint.r, endG: tint.g, endB: tint.b,
                )))
                ghost.commands.append(Command(easing: .linear, startTime: birth, endTime: death, payload: .parameter(.additive)))
                return ghost
            }
        }
        // Behind the light: the ghosts are its reflection, not something in
        // front of it.
        return ghosts + sprites
    }
}
