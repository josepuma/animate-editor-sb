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
        public static let fill = "fill"
        public static let flipH = "flipH"
        public static let flipV = "flipV"
        public static let gradientAngle = "gradientAngle"
        public static let gradientStart = "gradientStart"
        public static let gradientEnd = "gradientEnd"
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

        /// Which gradient shape this is, for the faded version of the image.
        var gradientShape: BuiltInSprite.GradientShape {
            switch self {
            case .square: .square
            case .circle: .circle
            case .ring: .ring
            }
        }
    }

    /// How the shape is filled in.
    ///
    /// An enum rather than a "gradient" toggle, because a toggle is a two-case
    /// enum that cannot grow: a pattern, a noise or a texture would have
    /// nowhere to go, and adding a second toggle beside the first leaves two
    /// controls free to contradict each other. It names the slot, not one of
    /// its values, so anything added later joins the list without renaming
    /// what is already there.
    public enum Fill: String, CaseIterable, Sendable {
        case solid = "Solid"
        case gradient = "Gradient"
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
            // A fade along a direction, in **alpha** rather than in colour.
            //
            // Every built-in image here is drawn white and tinted by its `_C`
            // command, so one texture serves every colour and the tint stays
            // animatable like any other property. Baking two colours in would
            // mint a texture per pair and take the colour out of the author's
            // hands — what this adds is *where* the shape is solid and where it
            // is gone; what colour it is stays a keyframe.
            EffectParameter(
                id: Param.fill,
                name: "Fill",
                group: "Shape",
                defaultValue: .choice(Fill.solid.rawValue),
                options: Fill.allCases.map(\.rawValue),
            ),
            // Coarse on purpose, and this is what keeps the atlas finite: the
            // ramp is drawn into the texture, so three axes multiply and a
            // continuous slider would mint one at every value it passes
            // through. Fifteen degrees of difference in a soft ramp is not a
            // difference anyone can see.
            EffectParameter(
                id: Param.gradientAngle,
                name: "Angle",
                group: "Shape",
                defaultValue: .number(0),
                range: 0...345,
                step: Double(BuiltInSprite.gradientAngleStep),
                unit: "°",
                presentation: .slider,
                shownWhen: .init(parameter: Param.fill, isAnyOf: [Fill.gradient.rawValue]),
            ),
            // Where the fade begins and ends along that direction. Outside them
            // the shape is held solid or clear, so the stops say *where the
            // fade happens* rather than where the shape exists.
            EffectParameter(
                id: Param.gradientStart,
                name: "Fade From",
                group: "Shape",
                defaultValue: .number(0),
                range: 0...1,
                step: Double(BuiltInSprite.gradientStopStep) / 100,
                presentation: .slider,
                shownWhen: .init(parameter: Param.fill, isAnyOf: [Fill.gradient.rawValue]),
            ),
            EffectParameter(
                id: Param.gradientEnd,
                name: "Fade To",
                group: "Shape",
                defaultValue: .number(1),
                range: 0...1,
                step: Double(BuiltInSprite.gradientStopStep) / 100,
                presentation: .slider,
                shownWhen: .init(parameter: Param.fill, isAnyOf: [Fill.gradient.rawValue]),
            ),
            // Mirroring, which is not the same as rotating.
            //
            // A rotation turns the shape *about its anchor*, so a left-anchored
            // bar spun 180° swings off the far side of its own edge and leaves
            // the stage. A flip inverts the image where it stands, which is
            // what a mirrored pair actually wants — the second half of a
            // symmetric layout, or a gradient that has to fall the other way
            // without moving.
            EffectParameter(
                id: Param.flipH,
                name: "Flip H",
                group: "Appearance",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.flipV,
                name: "Flip V",
                group: "Appearance",
                defaultValue: .toggle(false),
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
    /// The image a shape draws with, faded or not.
    ///
    /// The ramp is drawn *into* the texture, because the format has nothing
    /// that could fade one side of a sprite after the fact — the same reason a
    /// ring's weight is part of its image.
    private static func image(for kind: Kind, context: EffectContext) -> String {
        let thickness = context.number(Param.thickness)
        guard Fill(rawValue: context.choice(Param.fill)) == .gradient else {
            return kind.sprite(thickness: thickness)
        }
        return BuiltInSprite.gradient(
            shape: kind.gradientShape,
            angle: context.number(Param.gradientAngle),
            start: context.number(Param.gradientStart),
            end: context.number(Param.gradientEnd),
            thickness: thickness,
        )
    }

    public static func sourceSize(for kind: Kind) -> Double {
        switch kind {
        // Round shapes are drawn large: a curve magnified six times becomes a
        // staircase, while a straight edge survives it.
        case .circle, .ring: 512
        case .square: 64
        }
    }

    /// The size the image is actually drawn at, which a gradient changes.
    ///
    /// A ramp needs the texels for a different reason than a curve does: it is
    /// the *stretch* that bands, not the magnification of an edge. So a faded
    /// square is drawn large where a solid one does not need to be.
    static func sourceSize(for kind: Kind, fill: Fill) -> Double {
        fill == .gradient
            ? max(sourceSize(for: kind), BuiltInSprite.gradientSourceSize)
            : sourceSize(for: kind)
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
            filePath: Self.image(for: kind, context: context),
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
        let source = Self.sourceSize(
            for: kind,
            fill: Fill(rawValue: context.choice(Param.fill)) ?? .solid,
        )
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

        // Held for the whole clip, like the additive flag: a mirror is what the
        // shape *is*, not something it does partway through.
        if context.toggle(Param.flipH) {
            sprite.commands.append(Command(
                easing: .linear,
                startTime: 0,
                endTime: duration,
                payload: .parameter(.flipHorizontal),
            ))
        }
        if context.toggle(Param.flipV) {
            sprite.commands.append(Command(
                easing: .linear,
                startTime: 0,
                endTime: duration,
                payload: .parameter(.flipVertical),
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
