import Foundation

// ─── Audio Waves presets ─────────────────────────────────────────────────────
//
// Sized against their cost, not only their look. A segment writes three
// commands a frame and a dot one, so strands, smoothness and length multiply
// fast: six silky strands at full smoothness over eight seconds come to about
// 270,000 commands — a file osu! will not open. Each of these is tuned to stay
// under 20,000, and a test holds every audio preset to that.

public extension AudioWavesEffect {
    static let presets: [EffectPreset] = [oscilloscope, silkStrands, dottedFlow, waveRing]

    private static func preset(
        _ id: String,
        _ name: String,
        _ summary: String,
        duration: Double,
        _ values: [String: EffectValue],
    ) -> EffectPreset {
        EffectPreset(
            id: id,
            name: name,
            effectType: descriptor.type,
            summary: summary,
            duration: duration,
            values: descriptor.defaultValues.merging(values) { _, override in override },
            overrides: values,
            pack: "Audio",
        )
    }

    /// A saw drawn by the song: each tooth as tall as its band is loud, the
    /// bass end jagged and the treble end calm when the mix sits that way.
    static let oscilloscope = preset("oscilloscope", "Oscilloscope", "A jagged line, each tooth a band",
                                     duration: 8000, [
        Param.style: .choice(Style.zigzag.rawValue),
        Param.drawAs: .choice(Draw.line.rawValue),
        Param.points: .integer(32),
        Param.height: .number(90),
        Param.thickness: .number(4),
        Param.color: .color(EffectColor(r: 230, g: 90, b: 230)),
        Param.colorEnd: .color(EffectColor(r: 230, g: 90, b: 230)),
    ])

    /// Silk: a bundle of smooth strands, each hearing the song a moment after
    /// the one in front, so a hit runs down the bundle instead of lifting it
    /// as one block. Additive, so where the strands cross they brighten.
    static let silkStrands = preset("silk-strands", "Silk Strands", "Smooth strands flowing one after another",
                                    duration: 4000, [
        Param.style: .choice(Style.flowing.rawValue),
        Param.drawAs: .choice(Draw.line.rawValue),
        Param.points: .integer(16),
        Param.smoothness: .integer(2),
        Param.waves: .number(2.5), Param.flow: .number(0.35),
        Param.height: .number(110),
        Param.thickness: .number(2),
        Param.strands: .integer(4),
        Param.lag: .number(60), Param.spread: .number(10), Param.falloff: .number(0.6),
        Param.rate: .integer(12),
        Param.color: .color(EffectColor(r: 255, g: 245, b: 225)),
        Param.colorEnd: .color(EffectColor(r: 170, g: 150, b: 120)),
        Param.opacity: .number(0.8),
        Param.additive: .toggle(true),
    ])

    /// The dotted strands under the silk: the same wave drawn in points, which
    /// reads lighter and costs a third per sample.
    static let dottedFlow = preset("dotted-flow", "Dotted Flow", "A wave drawn in points, in strands",
                                   duration: 4000, [
        Param.style: .choice(Style.flowing.rawValue),
        Param.drawAs: .choice(Draw.dots.rawValue),
        Param.points: .integer(24),
        Param.smoothness: .integer(4),
        Param.waves: .number(2), Param.flow: .number(-0.25),
        Param.height: .number(90),
        Param.dotSize: .number(3),
        Param.strands: .integer(3),
        Param.lag: .number(80), Param.spread: .number(14), Param.falloff: .number(0.5),
        Param.rate: .integer(15),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 140, g: 140, b: 150)),
    ])

    /// A wave closed round a ring, riding in and out as the song plays.
    static let waveRing = preset("wave-ring", "Wave Ring", "A flowing wave closed round a ring",
                                 duration: 4000, [
        Param.layout: .choice(Layout.circle.rawValue),
        Param.radius: .number(110),
        Param.style: .choice(Style.flowing.rawValue),
        Param.drawAs: .choice(Draw.line.rawValue),
        Param.points: .integer(24),
        Param.smoothness: .integer(2),
        Param.waves: .number(6), Param.flow: .number(0.2),
        Param.height: .number(40),
        Param.thickness: .number(3),
        Param.strands: .integer(2),
        Param.lag: .number(90), Param.spread: .number(6),
        Param.rate: .integer(15),
        Param.color: .color(EffectColor(r: 120, g: 210, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 60, g: 100, b: 255)),
        Param.additive: .toggle(true),
    ])
}
