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

    /// A scope trace: the song rebuilt as a waveform — bass as long swells,
    /// treble as a fine shiver over them — with a second, fainter strand one
    /// frame behind as the phosphor's afterglow.
    ///
    /// The first version was a zigzag, and it read as a spring bouncing: every
    /// tooth alternating on a fixed rhythm, all of them jumping together. A
    /// real trace crosses the line where its frequencies happen to sum to zero.
    static let oscilloscope = preset("oscilloscope", "Oscilloscope", "A scope trace, with afterglow",
                                     duration: 4000, [
        Param.style: .choice(Style.signal.rawValue),
        Param.drawAs: .choice(Draw.line.rawValue),
        Param.points: .integer(24),
        Param.samples: .integer(64),
        Param.flow: .number(1.2),
        Param.height: .number(110),
        Param.thickness: .number(2.5),
        Param.strands: .integer(2),
        // One frame behind at 12fps, in place: the glow a trace leaves.
        Param.lag: .number(80), Param.spread: .number(0), Param.falloff: .number(0.7),
        Param.rate: .integer(12),
        Param.color: .color(EffectColor(r: 230, g: 110, b: 240)),
        Param.colorEnd: .color(EffectColor(r: 140, g: 40, b: 170)),
        Param.additive: .toggle(true),
    ])

    /// Silk: strands of the same signal, each mixing the bands with phases of
    /// its own, so they cross and braid — and each hearing the song a moment
    /// after the one in front, so a hit runs down the bundle.
    ///
    /// The first version slid one smooth wave from left to right; strands that
    /// were shifted copies of it read as a ribbon travelling, not as silk.
    static let silkStrands = preset("silk-strands", "Silk Strands", "Strands that braid and shiver with the song",
                                    duration: 4000, [
        Param.style: .choice(Style.signal.rawValue),
        Param.drawAs: .choice(Draw.line.rawValue),
        Param.points: .integer(16),
        Param.samples: .integer(32),
        Param.flow: .number(0.6),
        Param.height: .number(120),
        Param.thickness: .number(2),
        Param.strands: .integer(4),
        Param.lag: .number(60), Param.spread: .number(10), Param.falloff: .number(0.6),
        Param.rate: .integer(12),
        Param.color: .color(EffectColor(r: 255, g: 245, b: 225)),
        Param.colorEnd: .color(EffectColor(r: 170, g: 150, b: 120)),
        Param.opacity: .number(0.8),
        Param.additive: .toggle(true),
    ])

    /// The dotted strands under the silk: the same signal drawn in points,
    /// which reads lighter and costs a third per sample.
    static let dottedFlow = preset("dotted-flow", "Dotted Flow", "A signal drawn in points, in strands",
                                   duration: 4000, [
        Param.style: .choice(Style.signal.rawValue),
        Param.drawAs: .choice(Draw.dots.rawValue),
        Param.points: .integer(16),
        Param.samples: .integer(64),
        Param.flow: .number(0.5),
        Param.height: .number(90),
        Param.dotSize: .number(3),
        Param.strands: .integer(3),
        Param.lag: .number(80), Param.spread: .number(14), Param.falloff: .number(0.5),
        Param.rate: .integer(15),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 140, g: 140, b: 150)),
    ])

    /// A signal closed round a ring, shivering in and out as the song plays.
    /// Every frequency is a whole number of turns round it, so it meets itself.
    static let waveRing = preset("wave-ring", "Wave Ring", "A signal closed round a ring",
                                 duration: 4000, [
        Param.layout: .choice(Layout.circle.rawValue),
        Param.radius: .number(110),
        Param.style: .choice(Style.signal.rawValue),
        Param.drawAs: .choice(Draw.line.rawValue),
        Param.points: .integer(16),
        Param.samples: .integer(48),
        Param.flow: .number(0.8),
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
