import Foundation

// ─── Audio Bars presets ──────────────────────────────────────────────────────
//
// Every one is the same effect with its layout and element chosen, and costs
// what Audio Bars costs: a command per bar per frame. They sit in the Audio
// pack, and each is meant for a section — a drop, a chorus — rather than a
// whole song.

public extension AudioBarsEffect {
    static let presets: [EffectPreset] = [
        circularSpectrum, arcSpectrum, hexSpectrum, ledMeter, waveform, dotRing,
    ]

    private static func preset(
        _ id: String,
        _ name: String,
        _ summary: String,
        _ values: [String: EffectValue],
    ) -> EffectPreset {
        EffectPreset(
            id: id,
            name: name,
            effectType: descriptor.type,
            summary: summary,
            duration: 8000,
            values: descriptor.defaultValues.merging(values) { _, override in override },
            overrides: values,
            pack: "Audio",
        )
    }

    /// The circle every music channel uses: thin bars round a ring, mirrored
    /// so both halves answer the same frequencies and the shape stays
    /// symmetric. Additive and pale blue at the peaks, so the loud bands glow.
    static let circularSpectrum = preset("circular-spectrum", "Circular Spectrum",
                                         "Thin bars round a ring, mirrored", [
        Param.layout: .choice(Layout.circle.rawValue),
        Param.radius: .number(110),
        Param.bands: .integer(48),
        Param.width: .number(5), Param.gap: .number(0),
        Param.height: .number(90), Param.floorHeight: .number(4),
        Param.mirrored: .toggle(true),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
        Param.colorTop: .color(EffectColor(r: 130, g: 200, b: 255)),
        Param.additive: .toggle(true),
    ])

    /// Half a circle opening upward: a rainbow of bars over a title or a logo.
    static let arcSpectrum = preset("arc-spectrum", "Arc Spectrum", "Bars on a half circle", [
        Param.layout: .choice(Layout.arc.rawValue),
        Param.radius: .number(180), Param.arcSpan: .number(180),
        Param.bands: .integer(32),
        Param.width: .number(8), Param.gap: .number(0),
        Param.height: .number(80), Param.floorHeight: .number(4),
        Param.color: .color(EffectColor(r: 255, g: 210, b: 120)),
        Param.colorTop: .color(EffectColor(r: 255, g: 90, b: 60)),
    ])

    /// A hexagon of bars. The bars on each edge stand parallel, so the six
    /// sides read — a circle with corners would not.
    static let hexSpectrum = preset("hex-spectrum", "Hex Spectrum", "Bars along the sides of a hexagon", [
        Param.layout: .choice(Layout.polygon.rawValue),
        Param.sides: .integer(6), Param.radius: .number(120),
        Param.bands: .integer(48),
        Param.width: .number(5), Param.gap: .number(0),
        Param.height: .number(60), Param.floorHeight: .number(3),
        Param.color: .color(EffectColor(r: 200, g: 140, b: 255)),
        Param.colorTop: .color(EffectColor(r: 255, g: 255, b: 255)),
    ])

    /// The meter on every amplifier: green at the root, red at the top, each
    /// segment switching on as the band rises past it.
    static let ledMeter = preset("led-meter", "LED Meter", "Segmented columns, green to red", [
        Param.element: .choice(Element.segments.rawValue),
        Param.segments: .integer(10),
        Param.bands: .integer(16),
        Param.width: .number(20), Param.gap: .number(6),
        Param.height: .number(180),
        Param.color: .color(EffectColor(r: 60, g: 255, b: 110)),
        Param.colorTop: .color(EffectColor(r: 255, g: 60, b: 60)),
    ])

    /// Many small dots riding either side of a line: a waveform, made of the
    /// same thing as everything else here.
    static let waveform = preset("waveform", "Waveform", "Dots riding either side of a line", [
        Param.element: .choice(Element.dots.rawValue),
        Param.origin: .choice(Grounding.centre.rawValue),
        Param.bands: .integer(64),
        Param.width: .number(5), Param.gap: .number(5),
        Param.height: .number(120), Param.floorHeight: .number(0),
        Param.easing: .choice(Response.smooth.rawValue),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
    ])

    /// Dots round a ring, thrown out as their band plays.
    static let dotRing = preset("dot-ring", "Dot Ring", "Dots round a ring, thrown out by their band", [
        Param.layout: .choice(Layout.circle.rawValue),
        Param.element: .choice(Element.dots.rawValue),
        Param.radius: .number(100),
        Param.bands: .integer(40),
        Param.width: .number(10),
        Param.height: .number(70), Param.floorHeight: .number(0),
        Param.mirrored: .toggle(true),
        Param.color: .color(EffectColor(r: 255, g: 130, b: 190)),
    ])
}
