import Foundation

// ─── Backgrounds made of shapes ──────────────────────────────────────────────
//
// The still ones. A particle lives twenty seconds at most, so a backdrop that
// never moves cannot be a particle: a shape holds for its whole clip, however
// long that is.

public extension ShapeEffect {
    static let backgroundPresets: [EffectPreset] = [gradientBackdrop, vignette]

    private static func background(
        _ id: String,
        _ name: String,
        _ summary: String,
        _ values: [String: EffectValue],
        layers: [(String, [String: EffectValue])] = [],
    ) -> EffectPreset {
        EffectPreset(
            id: id,
            name: name,
            effectType: descriptor.type,
            summary: summary,
            duration: 20_000,
            values: descriptor.defaultValues.merging(values) { _, override in override },
            overrides: values,
            layers: layers.map { name, values in
                EffectPreset.Layer(
                    effectType: descriptor.type,
                    name: name,
                    values: descriptor.defaultValues.merging(values) { _, override in override },
                )
            },
            pack: "Backgrounds",
        )
    }

    /// Two colours, one fading into the other from the bottom up.
    ///
    /// The fill is an alpha ramp in one colour, not a two-colour ramp — so the
    /// backdrop is a solid frame with a faded frame over it. Two sprites, and
    /// both colours stay keyframeable.
    static let gradientBackdrop = background("gradient-backdrop", "Gradient Backdrop",
                                             "Two colours fading into each other", [
        Param.kind: .choice(Kind.square.rawValue),
        Param.width: .number(854), Param.height: .number(480),
        Param.color: .color(EffectColor(r: 18, g: 16, b: 48)),
    ], layers: [
        ("Glow", [
            Param.kind: .choice(Kind.square.rawValue),
            Param.width: .number(854), Param.height: .number(480),
            "x": .number(320), "y": .number(240),
            Param.fill: .choice(Fill.gradient.rawValue),
            // 90° is solid at the bottom, clear at the top — read off the
            // texture's own pixels, not assumed from the word "angle".
            Param.gradientAngle: .number(90),
            Param.gradientStart: .number(0), Param.gradientEnd: .number(1),
            Param.color: .color(EffectColor(r: 120, g: 50, b: 150)),
            Param.opacity: .number(0.8),
        ]),
    ])

    /// Darkened edges, drawing the eye to the middle. Four bars, each solid
    /// black at its edge and clear toward the centre — a fade is linear, so a
    /// round vignette is four straight ones.
    ///
    /// The angles were read off the gradient texture's pixels: 0° is solid on
    /// the left, 90° at the bottom, 180° on the right, 270° at the top.
    ///
    /// **The parent is an anchor that draws nothing**, sitting at the centre.
    /// A compound moves as one, so its parent's position carries every layer:
    /// the first version made the top bar the parent, set at y 0, and it
    /// dragged the other three 240px up the frame — the whole picture grey
    /// with a hard edge low down, which is what it looked like over white.
    static let vignette = background("vignette", "Vignette", "Darkened edges around the frame", [
        Param.kind: .choice(Kind.square.rawValue),
        Param.width: .number(854), Param.height: .number(480),
        Param.opacity: .number(0),
    ], layers: [
        ("Top", [
            Param.kind: .choice(Kind.square.rawValue),
            Param.origin: .choice(Origin.topCentre.rawValue),
            Param.width: .number(854), Param.height: .number(160),
            "x": .number(320), "y": .number(0),
            Param.fill: .choice(Fill.gradient.rawValue),
            Param.gradientAngle: .number(270),
            Param.color: .color(EffectColor(r: 0, g: 0, b: 0)),
            Param.opacity: .number(0.75),
        ]),
        ("Bottom", [
            Param.kind: .choice(Kind.square.rawValue),
            Param.origin: .choice(Origin.bottomCentre.rawValue),
            Param.width: .number(854), Param.height: .number(160),
            "x": .number(320), "y": .number(480),
            Param.fill: .choice(Fill.gradient.rawValue),
            Param.gradientAngle: .number(90),
            Param.color: .color(EffectColor(r: 0, g: 0, b: 0)),
            Param.opacity: .number(0.75),
        ]),
        ("Left", [
            Param.kind: .choice(Kind.square.rawValue),
            Param.origin: .choice(Origin.centreLeft.rawValue),
            Param.width: .number(220), Param.height: .number(480),
            "x": .number(-107), "y": .number(240),
            Param.fill: .choice(Fill.gradient.rawValue),
            Param.gradientAngle: .number(0),
            Param.color: .color(EffectColor(r: 0, g: 0, b: 0)),
            Param.opacity: .number(0.75),
        ]),
        ("Right", [
            Param.kind: .choice(Kind.square.rawValue),
            Param.origin: .choice(Origin.centreRight.rawValue),
            Param.width: .number(220), Param.height: .number(480),
            "x": .number(747), "y": .number(240),
            Param.fill: .choice(Fill.gradient.rawValue),
            Param.gradientAngle: .number(180),
            Param.color: .color(EffectColor(r: 0, g: 0, b: 0)),
            Param.opacity: .number(0.75),
        ]),
    ])
}
