import Foundation

public extension TextEffect {
    /// Text that does not stay flat: a look from a filter, a scene from
    /// compound layers, or particles the letters throw off themselves.
    ///
    /// Three kinds, because they answer three different things:
    /// - **Filters** change how the letters *look* — a neon glow, a split, a
    ///   trail. Only values; the filter library already draws them.
    /// - **Layers** put the title *in* something — a shockwave, embers, a
    ///   field converging. They wait (``EffectNode/delay``) for the moment the
    ///   letters land, because a burst that fires while the title is still in
    ///   flight reads as two unrelated things.
    /// - **Glyph particles** come from *each letter at its own moment*, which
    ///   is the one thing a layer cannot do: it knows nothing about the
    ///   stagger above it.
    ///
    /// Filed under their own pack: they are built things, and scattered among
    /// the plain movements they would read as variations on them.
    ///
    /// None sets content — text, font, size or base colour — so swapping to
    /// one never takes the author's words away.
    static let fxPresets: [EffectPreset] = [
        neonSign, rgbSplit, ghostTrail, focusIn, dropShadowPop,
        impactTitle, fireTitle, cosmicIntro, lyricSparkle, warpTitle,
        sparkLanding, dustDrop, cometTrail, disintegrate, emberType,
    ]

    static let fxPack = "Text FX"

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// A tube sign striking: letters appear at random and the glow stutters on
    /// before it settles.
    ///
    /// The flicker lives in the glow's keyframes, not in the letters: a sign
    /// that is already lit does not blink its tubes off, it buzzes.
    static let neonSign = preset(
        "neon-sign", "Neon Sign", "A pink glow stutters on, letters lit at random", [
            Param.stagger: .number(60),
            Param.staggerFrom: .choice("Random"),
            Param.fadeIn: .number(80),
            Param.fadeOut: .number(300),
            Param.easing: .choice("Linear"),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(
                type: GlowFilter.descriptor.type,
                values: [
                    GlowFilter.Param.radius: .number(16),
                    GlowFilter.Param.tinted: .toggle(true),
                    GlowFilter.Param.color: .color(EffectColor(r: 255, g: 70, b: 200)),
                ],
                animations: [GlowFilter.Param.intensity: KeyframeTrack([
                    Keyframe(time: 0, value: 0),
                    Keyframe(time: 120, value: 1.4),
                    Keyframe(time: 200, value: 0.3),
                    Keyframe(time: 320, value: 1.2),
                    Keyframe(time: 600, value: 0.9),
                ])],
            ),
        ],
    )

    /// Channels torn apart and twitching: the title as a broken signal.
    static let rgbSplit = preset(
        "rgb-split", "RGB Split", "Colour channels split and twitch", [
            Param.fadeIn: .number(200),
            Param.fadeOut: .number(300),
            Param.scaleFrom: .number(1.2),
            Param.easing: .choice("Expo"),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(type: ChromaticFilter.descriptor.type, values: [
                ChromaticFilter.Param.offset: .number(6),
                ChromaticFilter.Param.intensity: .number(0.8),
                ChromaticFilter.Param.jitter: .number(0.6),
                ChromaticFilter.Param.rate: .number(14),
            ]),
        ],
    )

    /// Letters streaking in from the left and leaving a fading blue wake.
    ///
    /// An echo only shows where something *was*, so the letters travel far
    /// and keep drifting while they hold — a still title would stack its
    /// copies on itself.
    static let ghostTrail = preset(
        "ghost-trail", "Ghost Trail", "Letters streak in leaving a blue wake", [
            Param.stagger: .number(40),
            Param.fadeIn: .number(700),
            Param.fadeOut: .number(400),
            Param.driftFrom: .number(-360),
            Param.driftX: .number(40),
            Param.easing: .choice("Expo"),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(type: EchoFilter.descriptor.type, values: [
                EchoFilter.Param.count: .integer(5),
                EchoFilter.Param.delay: .number(50),
                EchoFilter.Param.falloff: .number(0.6),
                EchoFilter.Param.shrink: .number(0.3),
                EchoFilter.Param.tint: .color(EffectColor(r: 90, g: 180, b: 255)),
            ]),
        ],
    )

    /// The title pulling into focus, the way a lens racks onto it.
    ///
    /// The blur is animated, not the letters' opacity: a cross-fade from
    /// blurred to sharp is a dimmer copy of the sharp one, never a blur in
    /// between. Capped at 16 because every step of radius it passes is
    /// another texture per letter.
    static let focusIn = preset(
        "focus-in", "Focus In", "The title racks into focus", [
            Param.fadeIn: .number(700),
            Param.fadeOut: .number(500),
            Param.scaleFrom: .number(1.12),
            Param.easing: .choice("Ease Out"),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(
                type: BlurFilter.descriptor.type,
                animations: [BlurFilter.Param.radius: KeyframeTrack([
                    Keyframe(time: 0, value: 16, easing: .quadOut),
                    Keyframe(time: 800, value: 0),
                ])],
            ),
        ],
    )

    /// Letters popping up off the page, each with a shadow under it.
    static let dropShadowPop = preset(
        "drop-shadow-pop", "Drop Shadow Pop", "Letters pop up off the page with a shadow", [
            Param.stagger: .number(50),
            Param.fadeIn: .number(350),
            Param.fadeOut: .number(300),
            Param.scaleFrom: .number(0),
            Param.easing: .choice("Back"),
            Param.exit: .choice("Shrink"),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(type: ShadowFilter.descriptor.type, values: [
                ShadowFilter.Param.offsetX: .number(6),
                ShadowFilter.Param.offsetY: .number(8),
                ShadowFilter.Param.opacity: .number(0.6),
                ShadowFilter.Param.softness: .number(6),
            ]),
        ],
    )

    // ─── Compounds ───────────────────────────────────────────────────────────
    //
    // A layer's position is absolute on the stage, and the text sits at its
    // centre (320, 240) — so a layer at y 240 is on the line, not 240 below it.

    /// A title slamming down and the stage reacting: a ring, a ring of
    /// sparks, dust kicked up off the floor of the line.
    ///
    /// Everything waits 220ms, which is exactly the slam: the impact is the
    /// letters arriving, not the moment they set off.
    static let impactTitle = preset(
        "impact-title", "Impact Title", "Slams down; a shockwave, sparks and dust hit with it", duration: 3000, [
            Param.fadeIn: .number(220),
            Param.fadeOut: .number(400),
            Param.scaleFrom: .number(3.2),
            Param.easing: .choice("Expo"),
        ],
        layers: [
            emitterLayer("shockwave", "Shockwave", delay: 220, [EmitterEffect.Param.y: .number(240)]),
            emitterLayer("sparks", "Sparks", delay: 220, [
                EmitterEffect.Param.y: .number(240), EmitterEffect.Param.count: .integer(60),
            ]),
            emitterLayer("dust", "Dust", delay: 220, [
                EmitterEffect.Param.y: .number(275), EmitterEffect.Param.width: .number(360),
            ]),
        ],
        pack: fxPack,
    )

    /// A title rising out of a bed of embers, warm with its own heat.
    ///
    /// The glow is on the clip, so it reaches the embers too: the letters and
    /// the fire share one light rather than sitting in front of it.
    static let fireTitle = preset(
        "fire-title", "Fire Title", "Rises over drifting embers, glowing warm", duration: 5000, [
            Param.stagger: .number(50),
            Param.fadeIn: .number(500),
            Param.fadeOut: .number(500),
            Param.riseFrom: .number(30),
        ],
        layers: [
            emitterLayer("embers", "Embers", delay: 200, [
                EmitterEffect.Param.y: .number(300),
                EmitterEffect.Param.width: .number(360),
                EmitterEffect.Param.count: .integer(140),
            ]),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(type: GlowFilter.descriptor.type, values: [
                GlowFilter.Param.radius: .number(14),
                GlowFilter.Param.intensity: .number(0.7),
                GlowFilter.Param.tinted: .toggle(true),
                GlowFilter.Param.color: .color(EffectColor(r: 255, g: 140, b: 40)),
            ]),
        ],
    )

    /// Letters assembling out of space while starlight converges on them,
    /// then a burst of warp lines the moment the title is whole.
    static let cosmicIntro = preset(
        "cosmic-intro", "Cosmic Intro", "Letters assemble as light converges, then a warp burst", duration: 4500, [
            Param.stagger: .number(20),
            Param.staggerFrom: .choice("Random"),
            Param.fadeIn: .number(900),
            Param.fadeOut: .number(500),
            Param.easing: .choice("Expo"),
            Param.scatterX: .number(260),
            Param.scatterY: .number(160),
            Param.scatterRotation: .number(120),
        ],
        layers: [
            emitterLayer("converge", "Converge", [
                EmitterEffect.Param.count: .integer(200),
                EmitterEffect.Param.life: .number(900),
                EmitterEffect.Param.width: .number(500),
                EmitterEffect.Param.height: .number(500),
            ]),
            emitterLayer("warp", "Warp", delay: 1000, [
                EmitterEffect.Param.emission: .choice(EmitterEffect.Emission.burst.rawValue),
                EmitterEffect.Param.count: .integer(160),
                EmitterEffect.Param.life: .number(1200),
            ]),
        ],
        pack: fxPack,
    )

    /// A karaoke line with glitter falling through it.
    static let lyricSparkle = preset(
        "lyric-sparkle", "Lyric Sparkle", "Words light up as glitter falls", duration: 5000, [
            Param.unit: .choice("Word"),
            Param.fadeIn: .number(200),
            Param.fadeOut: .number(300),
            Param.colourMode: .choice("Highlight"),
            Param.colour2: .color(EffectColor(r: 255, g: 220, b: 90)),
            Param.sweepStart: .number(10),
            Param.sweepLength: .number(70),
            Param.sweepEdge: .number(120),
        ],
        layers: [
            emitterLayer("glitter-fall", "Glitter", [EmitterEffect.Param.count: .integer(90)]),
        ],
        pack: fxPack,
    )

    /// A title punching out of the screen on a burst of light-speed lines.
    static let warpTitle = preset(
        "warp-title", "Warp Title", "Punches out of a burst of light-speed lines", duration: 3000, [
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(400),
            Param.scaleFrom: .number(0.2),
            Param.easing: .choice("Expo"),
        ],
        layers: [
            emitterLayer("warp", "Warp", delay: 250, [
                EmitterEffect.Param.emission: .choice(EmitterEffect.Emission.burst.rawValue),
                EmitterEffect.Param.count: .integer(220),
            ]),
        ],
        pack: fxPack,
        filters: [
            EffectPreset.Filter(type: GlowFilter.descriptor.type, values: [
                GlowFilter.Param.radius: .number(12),
                GlowFilter.Param.intensity: .number(0.6),
            ]),
        ],
    )

    // ─── Glyph particles ─────────────────────────────────────────────────────

    /// Letters dropping in and throwing golden sparks where each one hits.
    static let sparkLanding = preset(
        "spark-landing", "Spark Landing", "Each letter throws sparks as it lands", [
            Param.stagger: .number(70),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(300),
            Param.riseFrom: .number(-140),
            Param.easing: .choice("Bounce"),
            TextGlyphParticles.Param.mode: .choice("Land"),
            TextGlyphParticles.Param.count: .number(10),
            TextGlyphParticles.Param.size: .number(8),
            TextGlyphParticles.Param.speed: .number(220),
            TextGlyphParticles.Param.spread: .number(160),
            TextGlyphParticles.Param.gravity: .number(900),
            TextGlyphParticles.Param.colour: .color(EffectColor(r: 255, g: 210, b: 120)),
        ],
        pack: fxPack,
    )

    /// Letters thudding down and kicking up a little dust.
    ///
    /// Not additive: dust is matter, and matter covers what is behind it
    /// rather than adding light to it.
    static let dustDrop = preset(
        "dust-drop", "Dust Drop", "Letters thud down and kick up dust", [
            Param.stagger: .number(60),
            Param.fadeIn: .number(350),
            Param.fadeOut: .number(300),
            Param.riseFrom: .number(-100),
            Param.easing: .choice("Ease Out"),
            TextGlyphParticles.Param.mode: .choice("Land"),
            TextGlyphParticles.Param.count: .number(6),
            TextGlyphParticles.Param.sprite: .choice("Dust"),
            TextGlyphParticles.Param.size: .number(22),
            TextGlyphParticles.Param.speed: .number(70),
            TextGlyphParticles.Param.spread: .number(150),
            TextGlyphParticles.Param.gravity: .number(-20),
            TextGlyphParticles.Param.life: .number(1000),
            TextGlyphParticles.Param.colour: .color(EffectColor(r: 200, g: 190, b: 180)),
            TextGlyphParticles.Param.additive: .toggle(false),
        ],
        pack: fxPack,
    )

    /// Letters streaking in from the left, each with a tail of light.
    ///
    /// The tail is shed along the way, so it is where the letter *was*: it
    /// drifts back against the flight (Direction 180) and fades behind it.
    static let cometTrail = preset(
        "comet-trail", "Comet Trail", "Letters streak in with tails of light", [
            Param.stagger: .number(60),
            Param.fadeIn: .number(750),
            Param.fadeOut: .number(300),
            Param.driftFrom: .number(-420),
            Param.easing: .choice("Expo"),
            TextGlyphParticles.Param.mode: .choice("Trail"),
            TextGlyphParticles.Param.count: .number(14),
            TextGlyphParticles.Param.size: .number(7),
            TextGlyphParticles.Param.speed: .number(40),
            TextGlyphParticles.Param.direction: .number(180),
            TextGlyphParticles.Param.spread: .number(40),
            TextGlyphParticles.Param.life: .number(600),
            TextGlyphParticles.Param.colour: .color(EffectColor(r: 140, g: 200, b: 255)),
        ],
        pack: fxPack,
    )

    /// The title coming apart into drifting specks as it fades.
    ///
    /// A long fade-out is the whole effect: the specks leave over the exit,
    /// and the letter has to still be there for them to leave from.
    static let disintegrate = preset(
        "disintegrate", "Disintegrate", "Letters break into drifting specks as they fade", [
            Param.stagger: .number(40),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(1200),
            Param.riseFrom: .number(20),
            TextGlyphParticles.Param.mode: .choice("Disintegrate"),
            TextGlyphParticles.Param.count: .number(16),
            TextGlyphParticles.Param.sprite: .choice("Dot"),
            TextGlyphParticles.Param.size: .number(5),
            TextGlyphParticles.Param.speed: .number(70),
            TextGlyphParticles.Param.direction: .number(300),
            TextGlyphParticles.Param.spread: .number(70),
            TextGlyphParticles.Param.gravity: .number(-60),
            TextGlyphParticles.Param.life: .number(1300),
        ],
        pack: fxPack,
    )

    /// A typewriter whose every keystroke sends up a few embers.
    static let emberType = preset(
        "ember-type", "Ember Type", "Typed letters send up embers", [
            Param.stagger: .number(80),
            Param.fadeIn: .number(40),
            Param.fadeOut: .number(300),
            Param.easing: .choice("Linear"),
            TextGlyphParticles.Param.mode: .choice("Land"),
            TextGlyphParticles.Param.count: .number(5),
            TextGlyphParticles.Param.sprite: .choice("Ember"),
            TextGlyphParticles.Param.size: .number(18),
            TextGlyphParticles.Param.speed: .number(90),
            TextGlyphParticles.Param.spread: .number(70),
            TextGlyphParticles.Param.gravity: .number(-120),
            TextGlyphParticles.Param.life: .number(900),
            TextGlyphParticles.Param.colour: .color(EffectColor(r: 255, g: 150, b: 60)),
        ],
        pack: fxPack,
    )

    /// A layer made from one of the emitter's own presets, so a compound
    /// reuses numbers that were already tuned rather than a second set that
    /// drifts from them.
    private static func emitterLayer(
        _ presetID: String, _ name: String, delay: Double = 0, _ tweaks: [String: EffectValue] = [:],
    ) -> EffectPreset.Layer {
        let base = EmitterEffect.presets.first { $0.id == presetID }?.overrides ?? [:]
        return EffectPreset.Layer(
            effectType: EmitterEffect.descriptor.type,
            name: name,
            values: base.merging(tweaks) { _, new in new },
            delay: delay,
        )
    }
}
