import Foundation

// ─── Shapes that listen ──────────────────────────────────────────────────────
//
// A plain shape and a filter: the filter is what listens, which is why these
// could not exist until a preset could bring one. Each is cheap where it can
// be — the ones fired by hits cost a command per hit, not per frame.

public extension ShapeEffect {
    static let audioPresets: [EffectPreset] = [pulseRing, kickRipples, breathingGlow, beatFlash]

    private static func listening(
        _ id: String,
        _ name: String,
        _ summary: String,
        _ values: [String: EffectValue],
        filters: [EffectPreset.Filter],
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
            filters: filters,
        )
    }

    /// A ring that breathes with the bass: Audio Drive on its scale, with a
    /// long release so it swells on a kick and eases back rather than
    /// twitching.
    static let pulseRing = listening("pulse-ring", "Pulse Ring", "A ring that swells with the bass", [
        Param.kind: .choice(Kind.ring.rawValue),
        Param.width: .number(180), Param.height: .number(180),
    ], filters: [
        EffectPreset.Filter(type: AudioDriveFilter.descriptor.type, values: [
            AudioDriveFilter.Param.listenTo: .choice(EmitterEffect.AudioBand.bass.rawValue),
            AudioDriveFilter.Param.scale: .number(0.6),
            AudioDriveFilter.Param.smoothing: .number(0.7),
        ]),
    ])

    /// A ring opening out and dissolving on every kick: the pulse read
    /// backwards — born at rest, opening past it — fired by the song's hits
    /// instead of by the beat grid, so a kick off the grid still gets its
    /// ripple.
    static let kickRipples = listening("kick-ripples", "Kick Ripples", "A ring opening on every kick", [
        Param.kind: .choice(Kind.ring.rawValue),
        Param.width: .number(120), Param.height: .number(120),
    ], filters: [
        EffectPreset.Filter(type: PulseFilter.descriptor.type, values: [
            PulseFilter.Param.trigger: .choice(PulseFilter.Trigger.bass.rawValue),
            PulseFilter.Param.expand: .toggle(true),
            PulseFilter.Param.punch: .number(2),
            PulseFilter.Param.release: .number(1),
            PulseFilter.Param.decay: .number(0.9),
        ]),
    ])

    /// A soft light that breathes with the low end and dims in the quiet: a
    /// backdrop, not a subject. The glow is what makes a disc a light; the
    /// drive is what makes it follow the song.
    static let breathingGlow = listening("breathing-glow", "Breathing Glow",
                                         "A soft light that swells and dims with the song", [
        Param.kind: .choice(Kind.circle.rawValue),
        Param.width: .number(240), Param.height: .number(240),
        Param.color: .color(EffectColor(r: 255, g: 200, b: 140)),
        Param.opacity: .number(0.5),
    ], filters: [
        EffectPreset.Filter(type: GlowFilter.descriptor.type),
        EffectPreset.Filter(type: AudioDriveFilter.descriptor.type, values: [
            AudioDriveFilter.Param.listenTo: .choice(EmitterEffect.AudioBand.bass.rawValue),
            AudioDriveFilter.Param.scale: .number(0.25),
            AudioDriveFilter.Param.dim: .number(0.7),
            AudioDriveFilter.Param.smoothing: .number(0.85),
        ]),
    ])

    /// The whole frame flashing on every kick. Only the opacity moves — no
    /// punch — so it reads as light hitting the screen rather than as a box
    /// jumping. Faint on purpose: a full-strength flash on every kick is a
    /// strobe.
    static let beatFlash = listening("beat-flash", "Beat Flash", "The frame flashing on every kick", [
        Param.kind: .choice(Kind.square.rawValue),
        Param.width: .number(854), Param.height: .number(480),
        Param.opacity: .number(0.35),
    ], filters: [
        EffectPreset.Filter(type: PulseFilter.descriptor.type, values: [
            PulseFilter.Param.trigger: .choice(PulseFilter.Trigger.bass.rawValue),
            PulseFilter.Param.punch: .number(0),
            PulseFilter.Param.release: .number(1),
            PulseFilter.Param.decay: .number(0.6),
        ]),
    ])
}
