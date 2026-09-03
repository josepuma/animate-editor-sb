import Foundation

/// A drawn rectangle, circle, line or ring.
///
/// The dullest-sounding effect in the library and one of the most useful: bars,
/// frames, letterboxes, curtain wipes, underlines, vignettes and backdrops are
/// all rectangles, and without this each of them needs a PNG somebody drew and
/// remembered to ship. A shape needs neither.
///
/// **One sprite, whatever the size.** The shape is a texture stretched to the
/// dimensions asked for, not a row of tiles — so a full-width bar costs exactly
/// what a dot costs, and the file does not care how big the thing on screen is.
public struct ShapeEffect: Effect {
    public init() {}

    public enum Param {
        public static let kind = "kind"
        public static let origin = "origin"
        public static let thickness = "thickness"
        public static let width = "width"
        public static let height = "height"
        public static let color = "color"
        public static let opacity = "opacity"
        public static let additive = "additive"
    }

    /// What gets drawn.
    ///
    /// A short list on purpose. Anything more elaborate is artwork, and artwork
    /// belongs in a file the mapper drew — a shape effect that grew a polygon
    /// tool would be a worse drawing program bolted to a storyboard editor.
    public enum Kind: String, CaseIterable, Sendable {
        case square = "Square"
        case circle = "Circle"
        case ring = "Ring"

        /// The built-in image each one draws with.
        ///
        /// A ring's depends on how thick it is: the weight is drawn into the
        /// texture, so each one is a different image rather than the same image
        /// scaled.
        func sprite(thickness: Double) -> String {
            switch self {
            case .square: BuiltInSprite.fill
            case .circle: BuiltInSprite.disc
            case .ring: BuiltInSprite.hoop(thickness: thickness)
            }
        }
    }

    public static let descriptor = EffectDescriptor(
        type: "shape",
        name: "Shape",
        category: .generate,
        systemImage: "square.on.circle",
        parameters: [
            EffectParameter(
                id: Param.kind,
                name: "Shape",
                group: "Shape",
                defaultValue: .choice(Kind.square.rawValue),
                options: Kind.allCases.map(\.rawValue),
            ),
            // Which corner or edge the shape is positioned by.
            //
            // It matters more here than on an image: a letterbox bar is placed
            // against the top of the frame, not by its middle, and working out
            // "centre = height ÷ 2 above the edge" by hand is arithmetic the
            // origin exists to save.
            EffectParameter(
                id: Param.origin,
                name: "Origin",
                group: "Shape",
                defaultValue: .choice(Origin.centre.rawValue),
                options: Origin.allCases.map(\.rawValue),
            ),
            // In stage units, not as a scale factor.
            //
            // "854 wide" is the question someone has about a letterbox bar;
            // "×3.4 of whatever the texture happens to be" is not, and it
            // changes meaning the day the texture does.
            EffectParameter(
                id: Param.width,
                name: "Width",
                group: "Shape",
                defaultValue: .number(80),
                range: 1...2000,
                step: 10,
                unit: "px",
            ),
            EffectParameter(
                id: Param.height,
                name: "Height",
                group: "Shape",
                defaultValue: .number(80),
                range: 1...2000,
                step: 10,
                unit: "px",
            ),
            // Only a ring has one, and it is the first thing anyone reaches
            // for: a hairline and a thick band are different shapes, not the
            // same shape at different sizes.
            EffectParameter(
                id: Param.thickness,
                name: "Thickness",
                group: "Shape",
                defaultValue: .number(0.12),
                range: 0.01...0.5,
                step: 0.01,
                presentation: .slider,
                shownWhen: .init(parameter: Param.kind, isAnyOf: [Kind.ring.rawValue]),
            ),
            EffectParameter(
                id: Param.color,
                name: "Colour",
                group: "Appearance",
                defaultValue: .color(.white),
            ),
            EffectParameter(
                id: Param.opacity,
                name: "Opacity",
                group: "Appearance",
                defaultValue: .number(1),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.additive,
                name: "Additive",
                group: "Appearance",
                defaultValue: .toggle(false),
            ),
        ],
    )

    /// The size the built-in shapes are drawn at, which is what a stage-unit
    /// size has to be converted against.
    ///
    /// Stated here because `StoryboardCore` cannot see the renderer that draws
    /// them. A test checks the two agree — a mismatch would make every shape
    /// come out at the wrong size, and nothing would say why.
    public static func sourceSize(for kind: Kind) -> Double {
        switch kind {
        // Round shapes are drawn large: a curve magnified six times becomes a
        // staircase, while a straight edge survives it.
        case .circle, .ring: 512
        case .square: 64
        }
    }

    /// Kept for the tests that check one number against the renderer.
    public static let sourceSize: Double = 64

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let kind = Kind(rawValue: context.choice(Param.kind)) ?? .square
        let width = max(1, context.number(Param.width))
        let height = max(1, context.number(Param.height))
        let colour = context.color(Param.color)
        let opacity = context.number(Param.opacity)
        let additive = context.toggle(Param.additive)

        guard opacity > 0 else { return [] }

        var sprite = StoryboardSprite(
            id: "\(context.idPrefix)/shape",
            layer: .foreground,
            origin: Origin(osbName: context.choice(Param.origin)),
            filePath: kind.sprite(thickness: context.number(Param.thickness)),
            defaultX: TransformProperty.x.defaultValue,
            defaultY: TransformProperty.y.defaultValue,
        )

        let duration = context.duration

        // Held for the whole clip rather than faded in.
        //
        // A shape is placed, not performed: whatever entrance it should have is
        // the author's to keyframe, and one written in here would have to be
        // found and switched off before the plain case was available.
        sprite.commands.append(Command(
            easing: .linear,
            startTime: 0,
            endTime: duration,
            payload: .fade(start: opacity, end: opacity),
        ))

        // `_V`, because a shape is a size rather than a scale: the two axes are
        // set independently and a bar is nothing but a rectangle with very
        // different ones.
        let source = Self.sourceSize(for: kind)
        let scaleX = width / source
        let scaleY = height / source
        sprite.commands.append(Command(
            easing: .linear,
            startTime: 0,
            endTime: duration,
            payload: .vectorScale(
                startX: scaleX, startY: scaleY,
                endX: scaleX, endY: scaleY,
            ),
        ))

        if colour != .white {
            sprite.commands.append(Command(
                easing: .linear,
                startTime: 0,
                endTime: duration,
                payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                ),
            ))
        }

        if additive {
            sprite.commands.append(Command(
                easing: .linear,
                startTime: 0,
                endTime: duration,
                payload: .parameter(.additive),
            ))
        }

        return [sprite]
    }
}

// ─── Presets ─────────────────────────────────────────────────────────────────

public extension ShapeEffect {
    /// One per shape, each at a size that suits it.
    ///
    /// Square rather than a bar, because a shape is named for what it *is* and
    /// stretched into what it is wanted for. "Rectangle" already implied a
    /// proportion the shape does not have, and a "Line" preset was a square
    /// with one number changed — a name for a decision the author can make in a
    /// second, and one more thing to choose between for no gain.
    static let presets: [EffectPreset] = [
        preset(.square, "Square", "A filled square", width: 200, height: 200),
        preset(.circle, "Circle", "A filled disc", width: 200, height: 200),
        preset(.ring, "Ring", "An outlined circle", width: 200, height: 200),
    ]

    private static func preset(
        _ kind: Kind,
        _ name: String,
        _ summary: String,
        width: Double,
        height: Double,
    ) -> EffectPreset {
        EffectPreset(
            id: "shape-\(kind.rawValue.lowercased())",
            name: name,
            effectType: descriptor.type,
            summary: summary,
            duration: 2000,
            values: descriptor.defaultValues.merging([
                Param.kind: .choice(kind.rawValue),
                Param.width: .number(width),
                Param.height: .number(height),
            ]) { _, override in override },
        )
    }
}
