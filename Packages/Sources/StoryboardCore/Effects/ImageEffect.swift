import Foundation

/// One image on screen, with the handful of moves a storyboard sprite makes.
///
/// The plainest effect there is, and the one a storyboard is mostly made of: a
/// mapper wants their own artwork on screen far more often than they want a
/// particle field. Everything else here generates; this one places.
///
/// It is an ``Effect`` rather than a node type of its own because there is no
/// difference worth modelling. An effect turns parameters into sprites, and an
/// image on screen is one sprite — the timeline, the inspector, the filters and
/// the export already know what to do with that.
public struct ImageEffect: Effect {
    public init() {}

    public enum Param {
        public static let sprite = "sprite"
        public static let origin = "origin"
        public static let color = "color"
        public static let additive = "additive"
    }

    public static let descriptor = EffectDescriptor(
        type: "image",
        name: "Image",
        category: "Basic",
        systemImage: "photo",
        // Position, scale, rotation and opacity are absent on purpose: they are
        // keyframed on the node's `transform`, not declared as parameters.
        // Declaring them here as well would give the same property two homes
        // and let them disagree.
        parameters: [
            EffectParameter(
                id: Param.sprite,
                name: "Image",
                group: "Source",
                defaultValue: .text(""),
            ),
            EffectParameter(
                id: Param.origin,
                name: "Origin",
                group: "Source",
                defaultValue: .choice(Origin.centre.rawValue),
                options: Origin.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: Param.color,
                name: "Colour",
                group: "Appearance",
                defaultValue: .color(.white),
            ),
            EffectParameter(
                id: Param.additive,
                name: "Additive",
                group: "Appearance",
                defaultValue: .toggle(false),
            ),
        ],
    )

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let path = context.text(Param.sprite)
        // No image, nothing to draw. A clip with no file is a placeholder
        // someone is about to fill in, not an error.
        guard !path.isEmpty, context.duration > 0 else { return [] }

        // No transform commands here: the evaluator applies the clip's transform
        // to whatever every effect produces, so building them twice would apply
        // the same movement twice.
        var commands: [Command] = []

        let colour = context.color(Param.color)
        if colour != .white {
            commands.append(Command(
                easing: .linear, startTime: 0, endTime: 0,
                payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                ),
            ))
        }

        if context.toggle(Param.additive) {
            commands.append(Command(
                easing: .linear, startTime: 0, endTime: context.duration,
                payload: .parameter(.additive),
            ))
        }

        // A sprite's life is read from its commands, so it has to have one that
        // spans the clip. Without it the only command can be a zero-length hold
        // — a scale, say — and the sprite exists for a single instant before
        // vanishing, which looks exactly like a broken image.
        let spansTheClip = commands.contains {
            $0.kind != .parameter && $0.endTime > $0.startTime
        }
        if !spansTheClip {
            commands.append(Command(
                easing: .linear, startTime: 0, endTime: context.duration,
                payload: .fade(start: 1, end: 1),
            ))
        }

        return [StoryboardSprite(
            id: context.idPrefix,
            layer: context.node.layer,
            origin: Origin(osbName: context.choice(Param.origin)),
            filePath: path,
            // The canvas centre: the clip's transform moves it from here.
            defaultX: TransformProperty.x.defaultValue,
            defaultY: TransformProperty.y.defaultValue,
            commands: commands,
        )]
    }
}
