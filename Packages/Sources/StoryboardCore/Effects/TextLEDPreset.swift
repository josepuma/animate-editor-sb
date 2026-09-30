import Foundation

public extension TextEffect {
    /// Yellow LED lettering over a panel of unlit dots.
    ///
    /// The preset that shows what the LED filter is for: text, dots and a glow
    /// on one clip. **Order matters, and there are three filters for it**:
    ///
    /// 1. **Tint** first, because it replaces every sprite's colour — after the
    ///    LED filter it would also paint the panel's unlit dots yellow.
    /// 2. **LED** next, which adds the panel (in its own dim colour) and turns
    ///    every glyph into dots.
    /// 3. **Glow** last, so it blurs the *dot image*; the other way round the
    ///    dot filter would turn the halo's blurred copy into dots too. It
    ///    reaches the panel, faintly — unlit dots are dim enough that a halo
    ///    around them reads as bloom.
    ///
    /// The colour lives in the Tint rather than in the text's own colour
    /// parameter, and the preset leaves the size alone: a preset that sets
    /// content parameters gets them reset whenever the clip is swapped to a
    /// sibling, which is the author's words and size being taken away.
    static let ledSign = EffectPreset(
        id: "led-sign",
        name: "LED Sign",
        effectType: descriptor.type,
        summary: "Yellow dot-matrix lettering over a dim panel, with a glow",
        duration: 4000,
        values: descriptor.defaultValues.merging(ledSignValues) { _, override in override },
        overrides: ledSignValues,
        filters: [
            EffectPreset.Filter(type: TintFilter.descriptor.type, values: [
                TintFilter.Param.colour: .color(EffectColor(r: 255, g: 214, b: 48)),
            ]),
            EffectPreset.Filter(type: LEDFilter.descriptor.type, values: [
                LEDFilter.Param.pitch: .number(5),
                LEDFilter.Param.dotSize: .number(0.75),
                LEDFilter.Param.threshold: .number(0.3),
                LEDFilter.Param.panel: .choice(LEDFilter.Panel.stage.rawValue),
            ]),
            EffectPreset.Filter(type: GlowFilter.descriptor.type, values: [
                GlowFilter.Param.radius: .number(14),
                GlowFilter.Param.intensity: .number(0.6),
                GlowFilter.Param.tinted: .toggle(true),
                GlowFilter.Param.color: .color(EffectColor(r: 255, g: 190, b: 20)),
            ]),
        ],
    )

    /// Only how the letters arrive: a typewriter, which is what a sign does.
    private static let ledSignValues: [String: EffectValue] = [
        Param.stagger: .number(90),
        Param.fadeIn: .number(40),
        Param.fadeOut: .number(200),
        Param.easing: .choice("Linear"),
    ]
}
