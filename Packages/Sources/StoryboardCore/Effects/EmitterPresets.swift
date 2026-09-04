import Foundation

public extension EmitterEffect {
    /// The emitter's preset library.
    ///
    /// Each one is a physical read of the thing it imitates rather than a set
    /// of numbers that happened to look right: fire rises because hot air does,
    /// snow drifts because it is light enough to be carried, a shockwave is one
    /// burst that only scales. That is what makes them a starting point worth
    /// adjusting instead of a black box.
    static let presets: [EffectPreset] = [
        fire, smoke, sparks, snow, rain, storm, confetti, bubbles, stars, shockwave, magic,
        lightning, embers, flameJet, slashes, dust, bokeh, warp,
    ]

    private static func preset(
        _ id: String,
        _ name: String,
        _ summary: String,
        duration: Double = 4000,
        _ values: [String: EffectValue],
    ) -> EffectPreset {
        EffectPreset(
            id: id,
            name: name,
            effectType: descriptor.type,
            summary: summary,
            duration: duration,
            values: descriptor.defaultValues.merging(values) { _, override in override },
        )
    }

    // ─── Presets ─────────────────────────────────────────────────────────────

    /// Gravity is negative because hot air rises — the one case where inverting
    /// it is right. The narrow spread keeps the flame upright, and the wide,
    /// shallow emitter gives it a base: fire comes off a surface, and a point
    /// source reads as a jet.
    static let fire = preset("fire", "Fire", "Rising flame with a hot core", [
        Param.count: .integer(180),
        Param.emission: .choice(Emission.continuous.rawValue),
        Param.sprite: .text(BuiltInSprite.soft),
        Param.y: .number(400), Param.width: .number(60), Param.height: .number(10),
        Param.direction: .number(270), Param.spread: .number(18),
        Param.velocity: .number(90), Param.velocityRandom: .number(0.45),
        Param.gravity: .number(-40), Param.drag: .number(0.35),
        Param.life: .number(1100), Param.lifeRandom: .number(0.4),
        Param.scaleStart: .number(0.4), Param.scaleEnd: .number(0.06),
        Param.scaleRandom: .number(0.35), Param.spin: .number(40),
        Param.usesColorMid: .toggle(true),
        Param.color: .color(EffectColor(r: 255, g: 245, b: 200)),
        Param.colorMid: .color(EffectColor(r: 255, g: 140, b: 30)),
        Param.colorEnd: .color(EffectColor(r: 140, g: 20, b: 0)),
        Param.opacity: .number(0.85),
        Param.fadeIn: .number(0.12), Param.fadeOut: .number(0.6),
        Param.additive: .toggle(true),
    ])

    /// Smoke is fire slowed down and made to grow. Heavy drag is what makes it
    /// billow rather than fly, and it is **not** additive: smoke blocks light,
    /// it does not add to it — the single change that separates the two.
    static let smoke = preset("smoke", "Smoke", "Slow billowing cloud", [
        Param.count: .integer(55),
        Param.sprite: .text(BuiltInSprite.smoke),
        Param.y: .number(380), Param.width: .number(40), Param.height: .number(10),
        Param.direction: .number(270), Param.spread: .number(25),
        Param.velocity: .number(45), Param.velocityRandom: .number(0.5),
        Param.gravity: .number(-15), Param.drag: .number(0.6),
        Param.life: .number(3200), Param.lifeRandom: .number(0.35),
        // Scaled against the frame: the source is 512px, so 1.4 would be a
        // seven-hundred-pixel cloud — larger than the canvas is tall.
        Param.scaleStart: .number(0.12), Param.scaleEnd: .number(0.5),
        Param.scaleRandom: .number(0.4),
        Param.rotation: .number(360), Param.spin: .number(25),
        Param.color: .color(EffectColor(r: 160, g: 160, b: 165)),
        Param.colorEnd: .color(EffectColor(r: 70, g: 70, b: 78)),
        Param.opacity: .number(0.35),
        Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.55),
        Param.additive: .toggle(false),
    ])

    /// A burst, not a stream: sparks come from a single event. They keep their
    /// speed — almost no drag — and fall, which is what tells them apart from
    /// fire going the other way.
    static let sparks = preset("sparks", "Sparks", "Bright burst that falls and cools",
                               duration: 1400, [
        Param.count: .integer(140),
        Param.emission: .choice(Emission.burst.rawValue),
        Param.sprite: .text(BuiltInSprite.glow),
        Param.spread: .number(180), Param.direction: .number(270),
        Param.velocity: .number(380), Param.velocityRandom: .number(0.7),
        Param.gravity: .number(900), Param.drag: .number(0.1),
        Param.life: .number(900), Param.lifeRandom: .number(0.5),
        Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.02),
        Param.scaleRandom: .number(0.4),
        Param.color: .color(EffectColor(r: 255, g: 240, b: 190)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 70, b: 0)),
        Param.fadeIn: .number(0.02), Param.fadeOut: .number(0.5),
        Param.additive: .toggle(true),
    ])

    /// Slow and heavily dragged: snow is light enough that the air carries it,
    /// so it drifts instead of dropping. Emitted across the full width, above
    /// the screen, so it is already falling when it appears.
    static let snow = preset("snow", "Snow", "Drifting flakes across the screen",
                             duration: 10_000, [
        Param.count: .integer(260),
        Param.sprite: .text(BuiltInSprite.soft),
        Param.x: .number(320), Param.y: .number(-30),
        Param.width: .number(900), Param.height: .number(40),
        Param.direction: .number(95), Param.spread: .number(25),
        Param.velocity: .number(70), Param.velocityRandom: .number(0.6),
        Param.gravity: .number(20), Param.drag: .number(0.5),
        Param.life: .number(7000), Param.lifeRandom: .number(0.3),
        Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.16),
        Param.scaleRandom: .number(0.6),
        Param.opacity: .number(0.9),
        Param.fadeIn: .number(0.08), Param.fadeOut: .number(0.2),
    ])

    /// Rain is a texture, not a set of objects.
    ///
    /// Four things separate it from bars falling. It is **thin** — a drop is
    /// long and narrow, which needs `_V`, since buying length with uniform
    /// scale buys width with it. It is **aligned**: a drop falling at an angle
    /// has to point along that angle, or it slides sideways through its own
    /// path, which is what made the first version look wrong at every setting.
    /// It is **faint**, because any drop you can pick out individually is too
    /// solid. And it is **dense**, because rain reads as a field.
    ///
    /// The drops are emitted well above the frame and outlive it, so they are
    /// already at speed when they enter: rain that begins at the top edge looks
    /// poured from just off screen.
    ///
    /// `Direction` is the control worth reaching for — it is the wind.
    static let rain = preset("rain", "Rain", "Dense sheets of thin falling drops",
                             duration: 8000, [
        Param.count: .integer(700),
        Param.sprite: .text(BuiltInSprite.streak),
        Param.x: .number(320), Param.y: .number(-140),
        Param.width: .number(1500), Param.height: .number(140),
        Param.direction: .number(97), Param.spread: .number(1.5),
        Param.velocity: .number(1150), Param.velocityRandom: .number(0.3),
        Param.gravity: .number(300), Param.drag: .number(0),
        Param.life: .number(900), Param.lifeRandom: .number(0.25),
        Param.scaleStart: .number(0.07), Param.scaleEnd: .number(0.07),
        Param.scaleRandom: .number(0.45),
        Param.stretch: .number(9),
        Param.alignToMotion: .toggle(true),
        Param.rotation: .number(1.5),
        Param.color: .color(EffectColor(r: 190, g: 215, b: 255)),
        Param.opacity: .number(0.22),
        Param.fadeIn: .number(0.06), Param.fadeOut: .number(0.25),
        Param.additive: .toggle(true),
    ])

    /// Rain driven by wind: harder, faster and at a real slant.
    ///
    /// The difference from `rain` is almost entirely `direction` — 112° against
    /// 97° — which is the point worth showing. Weather is a wind angle and a
    /// density, and both are one parameter each.
    static let storm = preset("storm", "Storm", "Wind-driven rain at a hard slant",
                              duration: 8000, [
        Param.count: .integer(900),
        Param.sprite: .text(BuiltInSprite.streak),
        Param.x: .number(320), Param.y: .number(-160),
        // Wider than the frame: at a slant the drops travel a long way across,
        // so a box the width of the screen leaves the upwind corner empty.
        Param.width: .number(2200), Param.height: .number(160),
        Param.direction: .number(112), Param.spread: .number(2.5),
        Param.velocity: .number(1500), Param.velocityRandom: .number(0.3),
        Param.gravity: .number(220), Param.drag: .number(0),
        Param.life: .number(800), Param.lifeRandom: .number(0.3),
        Param.scaleStart: .number(0.08), Param.scaleEnd: .number(0.08),
        Param.scaleRandom: .number(0.5),
        Param.stretch: .number(12),
        Param.alignToMotion: .toggle(true),
        Param.rotation: .number(2),
        Param.color: .color(EffectColor(r: 200, g: 220, b: 255)),
        Param.opacity: .number(0.3),
        Param.fadeIn: .number(0.05), Param.fadeOut: .number(0.2),
        Param.additive: .toggle(true),
    ])

    /// Paper falling: many colours at once, tumbling, and thin.
    ///
    /// Three things the first version got wrong. Every piece was the same
    /// colour, because the colour ramp runs over a particle's *life* — right
    /// for fire, where the field cools together, and wrong for confetti, which
    /// is many colours at the same instant. That is what `Colour Variety` is
    /// for.
    ///
    /// It was also drawn as a solid square whatever it did, when paper is flat:
    /// edge-on it nearly vanishes. `Stretch` squashes one axis so a tumbling
    /// piece reads as a sheet rather than a chip.
    ///
    /// And it fell as one even sheet. Real confetti is thrown, so it arrives in
    /// gusts.
    static let confetti = preset("confetti", "Confetti", "Tumbling multicoloured paper",
                                 duration: 6000, [
        Param.count: .integer(200),
        Param.emission: .choice(Emission.bursts.rawValue),
        Param.burstCount: .integer(8),
        Param.sprite: .text(BuiltInSprite.square),
        Param.x: .number(320), Param.y: .number(-20),
        Param.width: .number(800), Param.height: .number(30),
        Param.direction: .number(90), Param.spread: .number(35),
        Param.velocity: .number(160), Param.velocityRandom: .number(0.6),
        Param.gravity: .number(260), Param.drag: .number(0.35),
        Param.life: .number(4500), Param.lifeRandom: .number(0.35),
        Param.scaleStart: .number(0.11), Param.scaleEnd: .number(0.11),
        Param.scaleRandom: .number(0.4),
        // Flattened, so a piece reads as paper rather than as a chip.
        Param.stretch: .number(0.45),
        Param.rotation: .number(360), Param.spin: .number(540),
        Param.color: .color(EffectColor(r: 255, g: 90, b: 120)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 90, b: 120)),
        // The whole wheel: confetti has no palette, it has all of them.
        Param.colorVariety: .number(1),
        Param.fadeIn: .number(0.03), Param.fadeOut: .number(0.15),
    ])

    /// The only preset with buoyancy: bubbles rise and *slow down* near the
    /// top, which the combination of negative gravity and strong drag gives
    /// for free.
    static let bubbles = preset("bubbles", "Bubbles", "Rising, wobbling and popping", [
        Param.count: .integer(70),
        Param.sprite: .text(BuiltInSprite.ring),
        Param.y: .number(500), Param.width: .number(500), Param.height: .number(30),
        Param.direction: .number(270), Param.spread: .number(12),
        Param.velocity: .number(110), Param.velocityRandom: .number(0.55),
        Param.gravity: .number(-30), Param.drag: .number(0.45),
        Param.life: .number(4000), Param.lifeRandom: .number(0.4),
        Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.24),
        Param.scaleRandom: .number(0.5),
        Param.color: .color(EffectColor(r: 200, g: 235, b: 255)),
        Param.opacity: .number(0.55),
        Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.1),
    ])

    /// Barely moving, long-lived and twinkling: a starfield is closer to a
    /// texture than to a particle system, and the motion has to stay under the
    /// threshold where the eye starts tracking individual points.
    static let stars = preset("stars", "Starfield", "Slow twinkling points", [
        Param.count: .integer(200),
        Param.sprite: .text(BuiltInSprite.star),
        Param.x: .number(320), Param.y: .number(240),
        Param.width: .number(880), Param.height: .number(500),
        Param.spread: .number(180),
        Param.velocity: .number(8), Param.velocityRandom: .number(0.8),
        Param.gravity: .number(0), Param.drag: .number(0),
        Param.life: .number(3000), Param.lifeRandom: .number(0.6),
        Param.scaleStart: .number(0.12), Param.scaleEnd: .number(0.2),
        Param.scaleRandom: .number(0.7),
        Param.rotation: .number(180), Param.spin: .number(20),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 160, g: 200, b: 255)),
        Param.opacity: .number(0.9),
        Param.fadeIn: .number(0.4), Param.fadeOut: .number(0.4),
        Param.additive: .toggle(true),
    ])

    /// One instant, one expanding ring. Everything is uniform on purpose —
    /// randomness would make an impact read as a spray instead of a single
    /// event.
    static let shockwave = preset("shockwave", "Shockwave", "A single expanding ring",
                                  duration: 700, [
        Param.count: .integer(1),
        Param.emission: .choice(Emission.burst.rawValue),
        Param.sprite: .text(BuiltInSprite.ring),
        Param.velocity: .number(0), Param.velocityRandom: .number(0),
        Param.spread: .number(0), Param.gravity: .number(0),
        Param.life: .number(700), Param.lifeRandom: .number(0),
        Param.scaleStart: .number(0.1), Param.scaleEnd: .number(4),
        Param.scaleRandom: .number(0),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
        Param.opacity: .number(0.9),
        Param.fadeIn: .number(0.05), Param.fadeOut: .number(0.8),
        Param.additive: .toggle(true),
    ])

    /// Drifting upward with no gravity to speak of: magic is the one effect
    /// with no physical rule to obey, so it borrows fire's rise and drops the
    /// weight.
    static let magic = preset("magic", "Magic", "Cyan sparks drifting upward", [
        Param.count: .integer(160),
        Param.sprite: .text(BuiltInSprite.glow),
        Param.y: .number(360), Param.width: .number(120), Param.height: .number(80),
        Param.direction: .number(270), Param.spread: .number(50),
        Param.velocity: .number(60), Param.velocityRandom: .number(0.7),
        Param.gravity: .number(-20), Param.drag: .number(0.4),
        Param.life: .number(2200), Param.lifeRandom: .number(0.5),
        Param.scaleStart: .number(0.3), Param.scaleEnd: .number(0.05),
        Param.scaleRandom: .number(0.5), Param.spin: .number(90),
        Param.usesColorMid: .toggle(true),
        Param.color: .color(EffectColor(r: 220, g: 255, b: 255)),
        Param.colorMid: .color(EffectColor(r: 80, g: 200, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 140, g: 60, b: 255)),
        Param.opacity: .number(0.8),
        Param.fadeIn: .number(0.2), Param.fadeOut: .number(0.5),
        Param.additive: .toggle(true),
    ])

    // ─── Presets that need a shipped texture ─────────────────────────────────
    //
    // These are the ones the drawn shapes cannot do. A branching bolt is not a
    // gradient with parameters on it: the picture *is* the effect, and the
    // emitter's job here is placement and timing rather than form.

    /// A storm, not a slideshow.
    ///
    /// Real lightning arrives as a flicker — three or four discharges inside a
    /// couple of hundred milliseconds, then nothing. One bolt at a time spread
    /// evenly is an image appearing on a timer, which is what made the first
    /// version of this preset dull: the emitter was dripping when it should
    /// have been striking.
    static let lightning = preset("lightning", "Lightning", "Flickering multi-strike storm",
                                  duration: 2600, [
        Param.count: .integer(18),
        Param.emission: .choice(Emission.bursts.rawValue),
        Param.burstCount: .integer(4),
        Param.sprite: .text(BuiltInSprite.lightning),
        Param.x: .number(320), Param.y: .number(190),
        Param.width: .number(680), Param.height: .number(240),
        Param.velocity: .number(0), Param.velocityRandom: .number(0),
        Param.spread: .number(0), Param.gravity: .number(0),
        // Short enough that the strikes inside one burst overlap into a
        // flicker rather than reading as separate images.
        Param.life: .number(150), Param.lifeRandom: .number(0.6),
        Param.scaleStart: .number(1.3), Param.scaleEnd: .number(1.45),
        Param.scaleRandom: .number(0.5),
        Param.rotation: .number(25),
        Param.color: .color(EffectColor(r: 220, g: 240, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 120, g: 160, b: 255)),
        // Almost no fade in: a bolt appears, it does not arrive.
        Param.fadeIn: .number(0.04), Param.fadeOut: .number(0.55),
        Param.additive: .toggle(true),
    ])

    /// The specks fire throws off: small, bright and short-lived.
    ///
    /// An ember is a *point* of burning matter. The first version of this
    /// preset used a noise texture at a large scale, which produced drifting
    /// clouds — the right motion attached to entirely the wrong thing, and it
    /// read as smoke lit from inside rather than as sparks.
    ///
    /// So the sprite is the smallest bright shape available and the scale is
    /// tiny. Everything else follows from that: many of them, because specks
    /// only register as a swarm; short-lived, because an ember cools; and
    /// additive, because they are the only light in the frame.
    static let embers = preset("embers", "Embers", "Small bright specks rising and cooling",
                               duration: 6000, [
        Param.count: .integer(260),
        Param.sprite: .text(BuiltInSprite.glow),
        Param.y: .number(430), Param.width: .number(280), Param.height: .number(30),
        Param.direction: .number(270), Param.spread: .number(28),
        Param.velocity: .number(75), Param.velocityRandom: .number(0.8),
        Param.gravity: .number(-35), Param.drag: .number(0.55),
        Param.life: .number(2200), Param.lifeRandom: .number(0.6),
        // A speck, not a cloud: at 512px a scale of 0.22 is a hundred pixels
        // across, which is what turned the first version into fog.
        Param.scaleStart: .number(0.05), Param.scaleEnd: .number(0.012),
        Param.scaleRandom: .number(0.6),
        Param.usesColorMid: .toggle(true),
        Param.color: .color(EffectColor(r: 255, g: 240, b: 190)),
        Param.colorMid: .color(EffectColor(r: 255, g: 150, b: 50)),
        Param.colorEnd: .color(EffectColor(r: 160, g: 30, b: 0)),
        Param.opacity: .number(0.9),
        Param.fadeIn: .number(0.06), Param.fadeOut: .number(0.5),
        Param.additive: .toggle(true),
    ])

    /// A flame with a silhouette, which changes what the emitter has to do.
    ///
    /// A shaped texture points somewhere. Spinning it at random — right for a
    /// round dot, where rotation is free variety — throws away the one thing
    /// the drawing contributes, and the result is upside-down flames tumbling
    /// past each other. So rotation stays near upright and the variety comes
    /// from size, timing and how far each one climbs.
    ///
    /// Emitted in bursts as well, because fire licks: a steady count is a gas
    /// flame, and this is meant to look like something burning.
    static let flameJet = preset("flame-jet", "Flame Jet", "Licking flames with real shape",
                                 duration: 5000, [
        Param.count: .integer(150),
        Param.emission: .choice(Emission.bursts.rawValue),
        Param.burstCount: .integer(30),
        Param.sprite: .text(BuiltInSprite.flame),
        Param.y: .number(410), Param.width: .number(70), Param.height: .number(8),
        Param.direction: .number(270), Param.spread: .number(9),
        Param.velocity: .number(150), Param.velocityRandom: .number(0.55),
        Param.gravity: .number(-90), Param.drag: .number(0.25),
        Param.life: .number(750), Param.lifeRandom: .number(0.45),
        // Grows before it dies: a flame widens as it lifts off, then thins.
        // 512px source: 0.9 would be a flame taller than the canvas.
        Param.scaleStart: .number(0.14), Param.scaleEnd: .number(0.34),
        Param.scaleRandom: .number(0.45),
        // A few degrees of lean, not a tumble.
        Param.rotation: .number(8), Param.spin: .number(0),
        Param.usesColorMid: .toggle(true),
        Param.color: .color(EffectColor(r: 255, g: 250, b: 225)),
        Param.colorMid: .color(EffectColor(r: 255, g: 150, b: 35)),
        Param.colorEnd: .color(EffectColor(r: 150, g: 25, b: 0)),
        Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.6),
        Param.additive: .toggle(true),
    ])

    /// Impact marks arriving in waves, the way a flurry of blows lands.
    ///
    /// A slash is a shaped stroke, so its rotation is limited rather than free:
    /// spun through a full circle the strokes point every which way and read as
    /// scattered debris. Kept within a wedge, they read as strikes from roughly
    /// the same direction.
    static let slashes = preset("slashes", "Slashes", "Waves of diagonal strikes",
                                duration: 1800, [
        Param.count: .integer(14),
        Param.emission: .choice(Emission.bursts.rawValue),
        Param.burstCount: .integer(5),
        Param.sprite: .text(BuiltInSprite.slash),
        Param.width: .number(300), Param.height: .number(200),
        Param.velocity: .number(60), Param.velocityRandom: .number(0.6),
        Param.direction: .number(300), Param.spread: .number(40),
        Param.gravity: .number(0),
        Param.life: .number(300), Param.lifeRandom: .number(0.35),
        Param.scaleStart: .number(0.8), Param.scaleEnd: .number(1.25),
        Param.scaleRandom: .number(0.35),
        // A wedge, not a circle: strikes come from a direction.
        Param.rotation: .number(45),
        Param.color: .color(EffectColor(r: 255, g: 255, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 180, g: 210, b: 255)),
        Param.fadeIn: .number(0.06), Param.fadeOut: .number(0.7),
        Param.additive: .toggle(true),
    ])

    /// Grit thrown up by an impact, hanging and then settling.
    ///
    /// Two mistakes made the first version fill the screen. It used a texture
    /// that is *already* a cloud of debris — hundreds of specks drawn into one
    /// image — as though it were a single particle, so ninety of them stacked
    /// into a wall. And it grew over its life, which is backwards: settling
    /// dust disperses and thins rather than expanding.
    ///
    /// The lesson generalises. A texture that is a whole effect cannot be a
    /// particle; a particle has to be one thing.
    /// Defocused highlights drifting across the frame.
    ///
    /// The preset that proves the shape parameters were the missing piece: a
    /// bokeh circle is *dimmer in its middle than at its rim* — the lens
    /// aperture projected rather than a point of light smeared — and none of
    /// the nine fixed textures could be that. Nor could a blur: measured, a
    /// blurred disc goes the other way, 1.00 → 0.62 → 0.49 across its radius,
    /// because blurring softens an edge and a bokeh has a hard one.
    ///
    /// Built from `core: 0.62, edge: 0.92, softness: 0.06` — a dim middle, a
    /// bright ring near the outside, and almost no fade past it.
    static let bokeh = preset("bokeh", "Bokeh", "Defocused highlights drifting past",
                              duration: 6000, [
        // Few and large, which is what depth of field does: a defocused
        // highlight is *bigger* than the light that made it, and a screen of
        // small ones reads as confetti.
        Param.count: .integer(46),
        Param.emission: .choice(Emission.continuous.rawValue),
        // Empty, so the three numbers below decide the shape.
        Param.sprite: .text(""),
        Param.core: .number(0.62),
        Param.edge: .number(0.92),
        Param.softness: .number(0.06),
        // The whole frame, since these are out-of-focus lights *behind*
        // whatever is sharp — not something emitted from a point.
        Param.width: .number(900), Param.height: .number(520),
        // Barely moving. A bokeh field drifts with the camera; particles that
        // travel read as sparks.
        Param.direction: .number(250), Param.spread: .number(80),
        Param.velocity: .number(18), Param.velocityRandom: .number(0.9),
        Param.drag: .number(0.2),
        // Long lives, so the field is dense without paying for more sprites —
        // the cheapest density there is.
        Param.life: .number(5200), Param.lifeRandom: .number(0.4),
        // The spread of sizes is the effect. A real defocused field has
        // circles several times each other's diameter, from lights at
        // different distances.
        Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.18),
        Param.scaleRandom: .number(0.85),
        Param.color: .color(EffectColor(r: 255, g: 196, b: 108)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 214, b: 150)),
        Param.colorVariety: .number(0.08),
        // Low, and additive: overlapping circles brightening where they cross
        // is what makes a bokeh field read as light rather than as discs.
        Param.opacity: .number(0.5),
        Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.3),
        Param.additive: .toggle(true),
    ])

    /// A warp: streaks rushing outward past the viewer from a vanishing point.
    ///
    /// Approach in 2D is scale, so every streak is born a speck at the centre
    /// and grows past the edge of the frame — the eye reads travel down a
    /// shaft rather than a circle getting bigger. Same illusion as a
    /// starfield, with streaks instead of points.
    ///
    /// `streak` is what makes it. A line drawn as a line is a piece of a light
    /// trail; built from dots this would be a bokeh cloud however it moved —
    /// and with a directional texture `Align to Motion` is not optional, or
    /// each streak faces the way it was drawn instead of the way it travels
    /// and the radial reads as confetti.
    ///
    /// Speed comes from `velocity × life`, not from drag: drag is exponential
    /// decay, so it would pack almost the whole journey into the first fifth
    /// of a life and leave the streaks parked for the rest.
    static let warp = preset("warp", "Warp", "Streaks rushing outward from a vanishing point",
                             duration: 6000, [
        // Density is what is on screen, not the count: ~330 alive at a time
        // over this clip. Long lives buy that for free, where more particles
        // cost a sprite each.
        Param.count: .integer(520),
        Param.sprite: .text(BuiltInSprite.streak),
        // A point, so everything shares one vanishing point. Radial sends them
        // outward from it; a few degrees of spread keeps the rays from looking
        // ruled.
        Param.shape: .choice(Shape.point.rawValue),
        Param.radial: .toggle(true),
        Param.spread: .number(3),
        Param.velocity: .number(320), Param.velocityRandom: .number(0.45),
        Param.life: .number(2200), Param.lifeRandom: .number(0.35),
        // The scale is the depth: a speck at the vanishing point to past the
        // edge of the screen.
        Param.scaleStart: .number(0.04), Param.scaleEnd: .number(0.30),
        Param.scaleRandom: .number(0.45),
        // Thin and long: the stretch multiplies a scale that is already
        // applied, so something elongated wants a small scale and a high
        // stretch rather than both large.
        Param.stretch: .number(5.5),
        Param.alignToMotion: .toggle(true),
        // Blue into magenta into deep blue. The mid costs one command per
        // particle and is the whole look — a flat tint reads as grey lines.
        Param.usesColorMid: .toggle(true),
        Param.color: .color(EffectColor(r: 120, g: 190, b: 255)),
        Param.colorMid: .color(EffectColor(r: 200, g: 80, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 60, g: 40, b: 180)),
        // Low, because additive stacks: at this density anything higher
        // saturates to white before the ramp has a chance to read, and the
        // bright core is meant to come from accumulation at the centre.
        Param.opacity: .number(0.30),
        Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.45),
        Param.additive: .toggle(true),
    ])

    static let dust = preset("dust", "Dust", "Grit kicked up by an impact, then settling",
                             duration: 2600, [
        Param.count: .integer(70),
        Param.emission: .choice(Emission.burst.rawValue),
        Param.sprite: .text(BuiltInSprite.smoke),
        Param.y: .number(440), Param.width: .number(180), Param.height: .number(16),
        // Outward and low, the way grit leaves a surface rather than a fountain.
        Param.direction: .number(270), Param.spread: .number(70),
        Param.velocity: .number(190), Param.velocityRandom: .number(0.85),
        Param.gravity: .number(260), Param.drag: .number(0.75),
        Param.life: .number(1600), Param.lifeRandom: .number(0.5),
        // Thinning, not growing: settling dust disperses.
        // Sized against the frame, not against the file: a 512px source at
        // 0.22 is a 110px puff, and seventy of those is a wall rather than a
        // scatter of grit.
        Param.scaleStart: .number(0.1), Param.scaleEnd: .number(0.03),
        Param.scaleRandom: .number(0.55),
        Param.rotation: .number(360), Param.spin: .number(70),
        Param.color: .color(EffectColor(r: 175, g: 158, b: 132)),
        Param.colorEnd: .color(EffectColor(r: 110, g: 98, b: 80)),
        Param.opacity: .number(0.35),
        Param.fadeIn: .number(0.08), Param.fadeOut: .number(0.6),
        Param.additive: .toggle(false),
    ])
}

// ─── Compound presets ────────────────────────────────────────────────────────

public extension EmitterEffect {
    /// Presets that arrive as several emitters at once.
    ///
    /// This is the step that separates a particle system people keep from one
    /// they try twice. Fire is not one emitter: it is a bright base, a body
    /// rising off it, embers leaving that, and a haze around the lot. Each of
    /// those wants a different sprite and a different set of numbers, so
    /// written as one emitter it becomes a compromise between four things and
    /// reads as none of them.
    static let compoundPresets: [EffectPreset] = [fireRing, portal, tunnel, impact, stormCell, energyOrb, arcReactor]

    /// Builds a layer with the emitter's own defaults underneath.
    ///
    /// Without the merge a layer would carry only what it names, and every
    /// parameter it left out would be missing rather than default — the
    /// evaluator reads them all.
    private static func layer(_ name: String, _ values: [String: EffectValue]) -> EffectPreset.Layer {
        EffectPreset.Layer(
            effectType: descriptor.type,
            name: name,
            values: descriptor.defaultValues.merging(values) { _, override in override },
        )
    }

    private static func compound(
        _ id: String,
        _ name: String,
        _ summary: String,
        duration: Double = 4000,
        _ values: [String: EffectValue],
        pack: String,
        layers: [EffectPreset.Layer],
    ) -> EffectPreset {
        EffectPreset(
            id: id,
            name: name,
            effectType: descriptor.type,
            summary: summary,
            duration: duration,
            values: descriptor.defaultValues.merging(values) { _, override in override },
            layers: layers,
            pack: pack,
        )
    }

    /// A burning circle: a dense rim of flame with fire rising from inside it.
    ///
    /// A real ring, now that the emitter can spawn on one. Two things had to be
    /// true before it read as one, and neither is about the shape:
    ///
    /// **A rim has to be dense.** Only the particles alive at one moment draw
    /// it — count spread over the duration divided by life — so a ring that is
    /// a circle in the model can still reach the eye as scattered dots with a
    /// curve implied between them. This carries a short life and a high count
    /// so the line is continuous.
    ///
    /// **Nothing else may out-cover it.** The first version drowned under its
    /// own embers: a long life and upward gravity gave them the top half of the
    /// frame, so the widest, busiest thing on screen was the layer meant to be
    /// an accent. They are fewer, smaller and shorter-lived than the fire now,
    /// which is what an accent is.
    static let fireRing = compound(
        "fire-ring", "Fire Ring", "A dense ring of flame with fire rising from its centre",
        duration: 6000,
        [
            // High count against a short life: what the eye sees is the number
            // alive at once, and a rim drawn by too few is a dotted line.
            Param.count: .integer(1150),
            Param.sprite: .text(BuiltInSprite.soft),
            Param.shape: .choice(Shape.ring.rawValue),
            // Wide and shallow: a circle on the ground is seen at an angle, and
            // a true circle reads as a hoop standing on its edge.
            Param.width: .number(300), Param.height: .number(300),
            Param.tilt: .number(70),
            Param.direction: .number(270), Param.spread: .number(45),
            Param.velocity: .number(32), Param.velocityRandom: .number(0.5),
            Param.gravity: .number(-18), Param.drag: .number(0.6),
            Param.life: .number(2400), Param.lifeRandom: .number(0.3),
            // Small: a particle the size of the ring's own thickness fills the
            // hole, and the shape goes with it.
            Param.scaleStart: .number(0.2), Param.scaleEnd: .number(0.05),
            Param.scaleRandom: .number(0.3),
            Param.usesColorMid: .toggle(true),
            Param.color: .color(EffectColor(r: 255, g: 190, b: 90)),
            Param.colorMid: .color(EffectColor(r: 255, g: 95, b: 20)),
            Param.colorEnd: .color(EffectColor(r: 110, g: 15, b: 5)),
            Param.opacity: .number(0.45),
            Param.fadeIn: .number(0.1), Param.fadeOut: .number(0.6),
            Param.additive: .toggle(true),
        ],
        pack: "Elements",
        layers: [
            // From inside the ring, and narrow enough to leave the rim visible:
            // a column as wide as the circle buries the near half of it.
            layer("Column", [
                Param.count: .integer(320),
                Param.sprite: .text(BuiltInSprite.soft),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(110), Param.height: .number(36),
                Param.direction: .number(270), Param.spread: .number(18),
                Param.velocity: .number(95), Param.velocityRandom: .number(0.5),
                Param.gravity: .number(-30), Param.drag: .number(0.6),
                Param.life: .number(1900), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.22), Param.scaleEnd: .number(0.03),
                Param.scaleRandom: .number(0.35),
                Param.usesColorMid: .toggle(true),
                Param.color: .color(EffectColor(r: 255, g: 175, b: 70)),
                Param.colorMid: .color(EffectColor(r: 250, g: 80, b: 18)),
                Param.colorEnd: .color(EffectColor(r: 80, g: 15, b: 15)),
                Param.opacity: .number(0.4),
                Param.fadeIn: .number(0.1), Param.fadeOut: .number(0.65),
                Param.additive: .toggle(true),
            ]),
            // Points of light, not little fires.
            //
            // `soft` rather than the ember texture: at the size an ember wants
            // to be, a texture with its own internal detail reads as a lumpy
            // brown smudge instead of a spark. Detail costs nothing at 40px
            // and is noise at 8.
            layer("Embers", [
                Param.count: .integer(130),
                Param.sprite: .text(BuiltInSprite.soft),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(220), Param.height: .number(70),
                Param.direction: .number(270), Param.spread: .number(35),
                Param.velocity: .number(80), Param.velocityRandom: .number(0.8),
                Param.gravity: .number(-30), Param.drag: .number(0.4),
                // Short enough that they die inside the fire's own height: an
                // accent that outlives the thing it accents becomes the subject.
                Param.life: .number(2000), Param.lifeRandom: .number(0.5),
                Param.scaleStart: .number(0.1), Param.scaleEnd: .number(0.01),
                Param.color: .color(EffectColor(r: 255, g: 210, b: 130)),
                Param.colorEnd: .color(EffectColor(r: 220, g: 70, b: 20)),
                Param.opacity: .number(0.8),
                Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
        ],
    )

    /// A gateway: a ring leaning away from the viewer, with light pouring
    /// through it.
    ///
    /// The tilt is the whole preset. A flat ellipse is a shape drawn on the
    /// screen; a ring whose particles are turned, sized and lit by where they
    /// sit on it is a circle standing in space — same sprite count, same
    /// commands, and the difference between a decoration and a doorway.
    ///
    /// Not the ring texture, deliberately: a ring sprite laid on a ring shape
    /// gives two hundred little hoops in a cloud, and the shape you built is
    /// lost inside the shape you drew. The rim is made of light, and the ring
    /// is what the light is arranged into.
    static let portal = compound(
        "portal", "Portal", "A ring leaning in space with light pouring through it",
        duration: 5000,
        [
            Param.count: .integer(1100),
            Param.sprite: .text(BuiltInSprite.soft),
            Param.shape: .choice(Shape.ring.rawValue),
            // A circle, not an ellipse: the lean is what flattens it, and
            // flattening the extents as well would count the same tilt twice.
            Param.width: .number(210), Param.height: .number(210),
            Param.tilt: .number(62),
            // Drifting outward off the rim, barely: a portal's edge holds its
            // shape, and particles that leave in a hurry are an explosion.
            Param.radial: .toggle(true),
            Param.spread: .number(30),
            Param.velocity: .number(16), Param.velocityRandom: .number(0.7),
            Param.drag: .number(0.7),
            Param.life: .number(2100), Param.lifeRandom: .number(0.3),
            Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.04),
            Param.scaleRandom: .number(0.3),
            Param.usesColorMid: .toggle(true),
            Param.color: .color(EffectColor(r: 190, g: 225, b: 255)),
            Param.colorMid: .color(EffectColor(r: 110, g: 130, b: 255)),
            Param.colorEnd: .color(EffectColor(r: 60, g: 30, b: 180)),
            // Low, so the rim brightens where particles pile up rather than
            // clipping to white on the second one.
            Param.opacity: .number(0.4),
            Param.fadeIn: .number(0.12), Param.fadeOut: .number(0.55),
            Param.additive: .toggle(true),
        ],
        pack: "Portals",
        layers: [
            // What is on the other side: a glow filling the opening, tilted
            // with it so it sits inside the ring rather than in front of it.
            layer("Throat", [
                Param.count: .integer(320),
                Param.sprite: .text(BuiltInSprite.glow),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(180), Param.height: .number(180),
                Param.tilt: .number(62),
                Param.velocity: .number(6),
                Param.life: .number(2600), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.35), Param.scaleEnd: .number(0.12),
                Param.scaleRandom: .number(0.4),
                Param.spin: .number(25),
                Param.color: .color(EffectColor(r: 90, g: 110, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 40, g: 20, b: 140)),
                Param.opacity: .number(0.22),
                Param.fadeIn: .number(0.3), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
            // Escaping upward through the opening, which is the one thing that
            // says the ring is a hole and not a disc.
            layer("Sparks", [
                Param.count: .integer(150),
                Param.sprite: .text(BuiltInSprite.sparkle),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(150), Param.height: .number(150),
                Param.tilt: .number(62),
                Param.direction: .number(270), Param.spread: .number(50),
                Param.velocity: .number(70), Param.velocityRandom: .number(0.8),
                Param.gravity: .number(-20), Param.drag: .number(0.3),
                Param.life: .number(1900), Param.lifeRandom: .number(0.5),
                Param.scaleStart: .number(0.12), Param.scaleEnd: .number(0.01),
                Param.spin: .number(180),
                Param.color: .color(EffectColor(r: 225, g: 245, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 110, g: 90, b: 255)),
                Param.opacity: .number(0.7),
                Param.fadeOut: .number(0.45),
                Param.additive: .toggle(true),
            ]),
        ],
    )

    // ─── Portals pack ────────────────────────────────────────────────────────

    /// A tunnel: rings rushing outward past the viewer, filling the screen.
    ///
    /// The trick is that a tunnel is a ring **coming at you**, and approach in
    /// 2D is scale. Every layer starts small at the centre and grows past the
    /// frame, so the eye reads travel down a shaft rather than a circle getting
    /// bigger — the same illusion as a starfield, with arcs instead of points.
    ///
    /// `twirl` is what makes it: an arc drawn as an arc is a piece of a hoop,
    /// and a scattering of them at one radius reads as a ring seen through
    /// motion. Built from dots it would be a bokeh cloud however it moved.
    ///
    /// Big on purpose. The other presets are objects placed in a frame; this
    /// one is the frame, and holding it to a polite two hundred pixels would be
    /// building a tunnel nobody travels down.
    static let tunnel = compound(
        "tunnel", "Tunnel", "Rings rushing outward past the viewer",
        duration: 6000,
        [
            Param.count: .integer(420),
            Param.sprite: .text(BuiltInSprite.arc),
            Param.shape: .choice(Shape.ring.rawValue),
            // A small ring: the growth is what carries them outward, and
            // starting wide skips the far end of the tunnel entirely.
            Param.width: .number(70), Param.height: .number(70),
            Param.radial: .toggle(true),
            Param.spread: .number(12),
            Param.velocity: .number(150), Param.velocityRandom: .number(0.35),
            Param.drag: .number(-0.25),
            Param.life: .number(2400), Param.lifeRandom: .number(0.25),
            // The scale is the depth: from a speck at the vanishing point to
            // past the edge of the screen.
            Param.scaleStart: .number(0.12), Param.scaleEnd: .number(2.6),
            Param.scaleRandom: .number(0.25),
            // Facing the way they travel, so each arc lies along the ring it
            // belongs to instead of pointing wherever it was drawn.
            Param.alignToMotion: .toggle(true),
            Param.spin: .number(15),
            Param.usesColorMid: .toggle(true),
            Param.color: .color(EffectColor(r: 120, g: 190, b: 255)),
            Param.colorMid: .color(EffectColor(r: 90, g: 110, b: 255)),
            Param.colorEnd: .color(EffectColor(r: 40, g: 20, b: 120)),
            Param.opacity: .number(0.5),
            Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.35),
            Param.additive: .toggle(true),
        ],
        pack: "Portals",
        layers: [
            // The walls: cloud rushing past, which is what gives the shaft a
            // surface. Without it the arcs are hoops in a void.
            layer("Walls", [
                Param.count: .integer(260),
                Param.sprite: .text(BuiltInSprite.cloud),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.width: .number(120), Param.height: .number(120),
                Param.radial: .toggle(true),
                Param.spread: .number(25),
                Param.velocity: .number(120), Param.velocityRandom: .number(0.5),
                Param.drag: .number(-0.2),
                Param.life: .number(2800), Param.lifeRandom: .number(0.35),
                Param.scaleStart: .number(0.3), Param.scaleEnd: .number(3.2),
                Param.scaleRandom: .number(0.4),
                Param.spin: .number(30),
                Param.color: .color(EffectColor(r: 70, g: 90, b: 220)),
                Param.colorEnd: .color(EffectColor(r: 20, g: 10, b: 70)),
                Param.opacity: .number(0.16),
                Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
            // Streaks along the walls: the speed lines. Long, thin and gone
            // quickly, which is what reads as fast.
            layer("Streaks", [
                Param.count: .integer(180),
                Param.sprite: .text(BuiltInSprite.boltThin),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.width: .number(90), Param.height: .number(90),
                Param.radial: .toggle(true),
                Param.spread: .number(8),
                Param.velocity: .number(320), Param.velocityRandom: .number(0.4),
                Param.drag: .number(-0.3),
                Param.life: .number(1400), Param.lifeRandom: .number(0.3),
                Param.scaleStart: .number(0.1), Param.scaleEnd: .number(1.8),
                Param.stretch: .number(2.5),
                Param.alignToMotion: .toggle(true),
                Param.color: .color(EffectColor(r: 220, g: 240, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 80, g: 120, b: 255)),
                Param.opacity: .number(0.55),
                Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.45),
                Param.additive: .toggle(true),
            ]),
            // The far end: the light you are heading towards.
            layer("Core", [
                Param.count: .integer(90),
                Param.sprite: .text(BuiltInSprite.flareSoft),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(50), Param.height: .number(50),
                Param.velocity: .number(8),
                Param.life: .number(2200), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.5), Param.scaleEnd: .number(0.9),
                Param.spin: .number(20),
                Param.color: .color(EffectColor(r: 210, g: 235, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 100, g: 130, b: 255)),
                Param.opacity: .number(0.3),
                Param.fadeIn: .number(0.3), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
        ],
    )

    // ─── Impact pack ─────────────────────────────────────────────────────────

    /// A hit: flash, shockwave, debris and smoke, in that order.
    ///
    /// An impact is a sequence, not a shape, and the layers are the beats of
    /// it. Every one of them is a texture code cannot draw — a muzzle flash has
    /// spokes, debris is gritty, smoke has body — which is the case these files
    /// exist for. Built from soft dots it would be a puff of light.
    static let impact = compound(
        "impact", "Impact", "A flash, a shockwave, debris and smoke",
        duration: 2200,
        [
            // The flash: everything at once, gone almost immediately. What
            // sells a hit is that the brightest moment is the shortest.
            Param.count: .integer(60),
            Param.sprite: .text(BuiltInSprite.muzzle),
            Param.emission: .choice(Emission.burst.rawValue),
            Param.shape: .choice(Shape.ellipse.rawValue),
            Param.width: .number(50), Param.height: .number(50),
            Param.spread: .number(360),
            Param.velocity: .number(90), Param.velocityRandom: .number(0.6),
            Param.drag: .number(0.8),
            Param.life: .number(320), Param.lifeRandom: .number(0.3),
            Param.scaleStart: .number(1.1), Param.scaleEnd: .number(0.2),
            Param.rotation: .number(360),
            Param.color: .color(EffectColor(r: 255, g: 250, b: 225)),
            Param.colorEnd: .color(EffectColor(r: 255, g: 170, b: 60)),
            Param.opacity: .number(0.7),
            Param.fadeOut: .number(0.6),
            Param.additive: .toggle(true),
        ],
        pack: "Impact",
        layers: [
            // The ring going out: one burst that only grows, which is what a
            // shockwave is. Flat on the ground, so it spreads rather than
            // hangs.
            layer("Shockwave", [
                Param.count: .integer(140),
                Param.sprite: .text(BuiltInSprite.crescent),
                Param.emission: .choice(Emission.burst.rawValue),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.width: .number(60), Param.height: .number(60),
                Param.tilt: .number(65),
                Param.radial: .toggle(true),
                Param.spread: .number(10),
                Param.velocity: .number(420), Param.velocityRandom: .number(0.2),
                Param.drag: .number(0.85),
                Param.life: .number(650),
                Param.scaleStart: .number(0.2), Param.scaleEnd: .number(0.7),
                Param.alignToMotion: .toggle(true),
                Param.color: .color(EffectColor(r: 255, g: 235, b: 200)),
                Param.colorEnd: .color(EffectColor(r: 200, g: 90, b: 30)),
                Param.opacity: .number(0.5),
                Param.fadeOut: .number(0.7),
                Param.additive: .toggle(true),
            ]),
            // Debris: thrown out and falling back. The only layer with real
            // gravity, and the one that says the hit had mass.
            layer("Debris", [
                Param.count: .integer(120),
                Param.sprite: .text(BuiltInSprite.debris),
                Param.emission: .choice(Emission.burst.rawValue),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(40), Param.height: .number(30),
                Param.direction: .number(270), Param.spread: .number(130),
                // Thrown hard but brought back quickly: debris that leaves the
                // frame spends its life where nobody is looking, and every one
                // of those commands is still in the file.
                Param.velocity: .number(150), Param.velocityRandom: .number(0.7),
                Param.gravity: .number(260), Param.drag: .number(0.5),
                Param.life: .number(1100), Param.lifeRandom: .number(0.45),
                Param.scaleStart: .number(0.22), Param.scaleEnd: .number(0.1),
                Param.scaleRandom: .number(0.6),
                Param.rotation: .number(360), Param.spin: .number(260),
                Param.color: .color(EffectColor(r: 190, g: 150, b: 110)),
                Param.colorEnd: .color(EffectColor(r: 90, g: 60, b: 45)),
                Param.opacity: .number(0.8),
                Param.fadeOut: .number(0.3),
            ]),
            // Smoke: the slowest, and the last thing left. Not additive —
            // smoke blocks light, it does not add to it.
            layer("Smoke", [
                Param.count: .integer(100),
                Param.sprite: .text(BuiltInSprite.cloud),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(80), Param.height: .number(40),
                Param.direction: .number(270), Param.spread: .number(80),
                Param.velocity: .number(60), Param.velocityRandom: .number(0.7),
                Param.gravity: .number(-25), Param.drag: .number(0.75),
                Param.life: .number(1800), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.3), Param.scaleEnd: .number(1.1),
                Param.scaleRandom: .number(0.5),
                Param.spin: .number(50),
                Param.color: .color(EffectColor(r: 120, g: 110, b: 105)),
                Param.colorEnd: .color(EffectColor(r: 40, g: 36, b: 34)),
                Param.opacity: .number(0.3),
                Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.6),
            ]),
        ],
    )

    /// A storm cell: branching bolts over cloud, with the flash they cast.
    ///
    /// Lightning is the clearest case for a drawn texture. A bolt branches, and
    /// nothing in a closed-form trajectory branches — approximated with dots it
    /// is a dotted line, which is not what anybody means by lightning.
    static let stormCell = compound(
        "storm-cell", "Storm Cell", "Branching bolts over cloud, with the flash they cast",
        duration: 4000,
        [
            // In clumps: lightning strikes two or three times and then stops.
            // Spread evenly it is a metronome, not weather.
            Param.count: .integer(26),
            Param.sprite: .text(BuiltInSprite.bolt),
            Param.emission: .choice(Emission.bursts.rawValue),
            Param.burstCount: .integer(4),
            Param.shape: .choice(Shape.rectangle.rawValue),
            Param.width: .number(420), Param.height: .number(150),
            Param.velocity: .number(12),
            Param.life: .number(260), Param.lifeRandom: .number(0.4),
            Param.scaleStart: .number(1.3), Param.scaleEnd: .number(1.3),
            Param.scaleRandom: .number(0.45),
            Param.stretch: .number(1.6),
            Param.rotation: .number(24),
            Param.color: .color(EffectColor(r: 235, g: 240, b: 255)),
            Param.colorEnd: .color(EffectColor(r: 150, g: 180, b: 255)),
            Param.opacity: .number(0.9),
            Param.fadeOut: .number(0.5),
            Param.additive: .toggle(true),
        ],
        pack: "Impact",
        layers: [
            // The glow a strike throws on the cloud around it, timed in the
            // same clumps so the sky lights with the bolt rather than beside it.
            layer("Flash", [
                Param.count: .integer(50),
                Param.sprite: .text(BuiltInSprite.flareSoft),
                Param.emission: .choice(Emission.bursts.rawValue),
                Param.burstCount: .integer(4),
                Param.width: .number(400), Param.height: .number(140),
                Param.velocity: .number(6),
                Param.life: .number(420), Param.lifeRandom: .number(0.5),
                Param.scaleStart: .number(2.2), Param.scaleEnd: .number(2.8),
                Param.scaleRandom: .number(0.4),
                Param.color: .color(EffectColor(r: 190, g: 205, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 70, g: 90, b: 170)),
                Param.opacity: .number(0.22),
                Param.fadeIn: .number(0.1), Param.fadeOut: .number(0.7),
                Param.additive: .toggle(true),
            ]),
            // The cloud it happens inside. Slow, wide and dim: it is the stage,
            // not the event.
            layer("Cloud", [
                Param.count: .integer(150),
                Param.sprite: .text(BuiltInSprite.cloudWisp),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(520), Param.height: .number(170),
                Param.direction: .number(180), Param.spread: .number(50),
                Param.velocity: .number(18), Param.velocityRandom: .number(0.7),
                Param.drag: .number(0.3),
                Param.life: .number(3200), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.5), Param.scaleEnd: .number(0.85),
                Param.scaleRandom: .number(0.4),
                Param.spin: .number(12),
                Param.color: .color(EffectColor(r: 90, g: 100, b: 130)),
                Param.colorEnd: .color(EffectColor(r: 30, g: 34, b: 50)),
                Param.opacity: .number(0.3),
                Param.fadeIn: .number(0.2), Param.fadeOut: .number(0.5),
            ]),
        ],
    )

    // ─── Energy pack ─────────────────────────────────────────────────────────

    /// A contained sphere of energy: banded shell, beam through the poles, halo
    /// around it.
    ///
    /// Three readings of one object, and the bands are what make it a solid.
    /// Drawn as scattered points a sphere is a ball of dots; drawn as *rings*
    /// the eye traces each band around the back and reads a surface — the same
    /// reason a wireframe globe looks spherical with nothing filled in.
    ///
    /// The beam is not decoration. A shell alone is ambiguous about which way
    /// it faces, and light escaping through the poles names the axis.
    static let energyOrb = compound(
        "energy-orb", "Energy Orb", "A banded sphere with light escaping its poles",
        duration: 5000,
        [
            Param.count: .integer(1100),
            Param.sprite: .text(BuiltInSprite.soft),
            Param.shape: .choice(Shape.sphere.rawValue),
            Param.width: .number(220), Param.height: .number(220),
            Param.bands: .integer(9),
            Param.tilt: .number(58),
            // Barely moving: a contained sphere holds its shape, and particles
            // that leave in a hurry are an explosion.
            Param.velocity: .number(10), Param.velocityRandom: .number(0.6),
            Param.drag: .number(0.7),
            Param.life: .number(2300), Param.lifeRandom: .number(0.3),
            Param.scaleStart: .number(0.13), Param.scaleEnd: .number(0.04),
            Param.scaleRandom: .number(0.3),
            Param.usesColorMid: .toggle(true),
            Param.color: .color(EffectColor(r: 235, g: 200, b: 255)),
            Param.colorMid: .color(EffectColor(r: 190, g: 110, b: 255)),
            Param.colorEnd: .color(EffectColor(r: 90, g: 30, b: 180)),
            // Low, so the shell brightens where bands cross rather than
            // clipping to white on the second particle.
            Param.opacity: .number(0.4),
            Param.fadeIn: .number(0.12), Param.fadeOut: .number(0.5),
            Param.additive: .toggle(true),
        ],
        pack: "Energy",
        layers: [
            // The column through the poles.
            //
            // A handful of large, still sprites — **not** a stream of
            // particles. A steady beam has no particles in it: it has a shape,
            // a place and an opacity, and `trace_01` is that shape already
            // drawn. Simulated with three hundred streaks it came out as a
            // pincushion, because every one of them pointed wherever it
            // happened to be thrown.
            //
            // Two sprites instead of three hundred, and it reads better.
            layer("Beam", [
                Param.count: .integer(10),
                Param.sprite: .text(BuiltInSprite.beam),
                Param.shape: .choice(Shape.point.rawValue),
                // Still. Velocity on a beam is what turned it into a swarm.
                Param.velocity: .number(0),
                Param.life: .number(2600), Param.lifeRandom: .number(0.25),
                // Sized against the sphere, not by eye.
                //
                // `trace_01` is 512px square, so scale is a multiplier on
                // *that*: 1.3 with a 2.2 stretch came out 666 × 1465, three
                // times the height of the stage. The sphere is 220 across, and
                // a beam wants to overhang it — not dwarf the canvas.
                Param.scaleStart: .number(0.5), Param.scaleEnd: .number(0.62),
                Param.scaleRandom: .number(0.15),
                Param.stretch: .number(1.5),
                Param.color: .color(EffectColor(r: 235, g: 220, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 150, g: 90, b: 255)),
                // Very low, because they stack: a dozen overlapping columns at
                // full strength is a white bar, not a beam.
                Param.opacity: .number(0.16),
                Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
            // The glow it sits in. Wider than the shell and much dimmer: a
            // sphere this bright would light the air around it.
            layer("Halo", [
                Param.count: .integer(180),
                Param.sprite: .text(BuiltInSprite.glow),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(240), Param.height: .number(240),
                Param.velocity: .number(5),
                Param.life: .number(2600), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.7), Param.scaleEnd: .number(1.1),
                Param.scaleRandom: .number(0.4),
                Param.spin: .number(18),
                Param.color: .color(EffectColor(r: 170, g: 100, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 60, g: 20, b: 140)),
                Param.opacity: .number(0.16),
                Param.fadeIn: .number(0.3), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
            // Sparks caught in the field, on the surface with the bands.
            layer("Sparks", [
                Param.count: .integer(160),
                Param.sprite: .text(BuiltInSprite.sparkle),
                Param.shape: .choice(Shape.sphere.rawValue),
                Param.width: .number(215), Param.height: .number(215),
                Param.bands: .integer(9),
                Param.tilt: .number(58),
                Param.velocity: .number(14), Param.velocityRandom: .number(0.9),
                Param.life: .number(1100), Param.lifeRandom: .number(0.5),
                Param.scaleStart: .number(0.14), Param.scaleEnd: .number(0.02),
                Param.spin: .number(150),
                Param.color: .color(EffectColor(r: 255, g: 250, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 190, g: 140, b: 255)),
                Param.opacity: .number(0.8),
                Param.fadeOut: .number(0.45),
                Param.additive: .toggle(true),
            ]),
        ],
    )

    /// A core with rings orbiting it, tilted apart like a gyroscope.
    ///
    /// The counterpart to the orb: where that one is a closed shell, this is
    /// open structure. Two rings at different leans read as crossing in space,
    /// which no single ring does however it is tuned.
    static let arcReactor = compound(
        "arc-reactor", "Arc Reactor", "A bright core inside crossing rings",
        duration: 5000,
        [
            Param.count: .integer(820),
            Param.sprite: .text(BuiltInSprite.soft),
            Param.shape: .choice(Shape.ring.rawValue),
            Param.width: .number(230), Param.height: .number(230),
            Param.tilt: .number(72),
            Param.radial: .toggle(true),
            // Running **around** the ring rather than off it.
            //
            // A ring of particles cannot rotate as an object — each one is born
            // where it is born and stays on its own path — so travel along the
            // rim is the only way a ring circulates in this format. Without it
            // the two rings sit dead still while everything around them moves,
            // and stillness beside motion reads as broken rather than as calm.
            Param.swirl: .number(90),
            Param.spread: .number(4),
            // Short hops, not orbits.
            //
            // A tangent is a **straight line** and the ring is curved, so a
            // particle travelling along it leaves immediately — measured, a
            // long path opened the ring from 80px to 138. Nothing in a closed
            // trajectory can follow a curve, so the ring holds its shape by
            // each particle covering only a short arc before it dies, with a
            // fresh one behind it. What the eye reads as rotation is the
            // procession, not any single dash going round.
            Param.velocity: .number(95), Param.velocityRandom: .number(0.3),
            Param.drag: .number(0.4),
            Param.life: .number(780), Param.lifeRandom: .number(0.3),
            Param.scaleStart: .number(0.14), Param.scaleEnd: .number(0.04),
            Param.usesColorMid: .toggle(true),
            Param.color: .color(EffectColor(r: 200, g: 245, b: 255)),
            Param.colorMid: .color(EffectColor(r: 80, g: 190, b: 255)),
            Param.colorEnd: .color(EffectColor(r: 20, g: 70, b: 190)),
            Param.opacity: .number(0.45),
            Param.fadeIn: .number(0.12), Param.fadeOut: .number(0.5),
            Param.additive: .toggle(true),
        ],
        pack: "Energy",
        layers: [
            // The second ring, leaning the other way — the crossing is what
            // reads as structure rather than as one thick band.
            layer("Cross Ring", [
                Param.count: .integer(700),
                Param.sprite: .text(BuiltInSprite.soft),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.width: .number(180), Param.height: .number(180),
                Param.tilt: .number(28),
                Param.radial: .toggle(true),
                // The other way round. Two rings turning against each other is
                // what reads as a mechanism; both the same way is a swirl.
                Param.swirl: .number(-90),
                Param.spread: .number(4),
                Param.velocity: .number(82), Param.velocityRandom: .number(0.3),
                Param.drag: .number(0.4),
                Param.life: .number(820), Param.lifeRandom: .number(0.3),
                Param.scaleStart: .number(0.12), Param.scaleEnd: .number(0.03),
                Param.color: .color(EffectColor(r: 180, g: 230, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 30, g: 90, b: 210)),
                Param.opacity: .number(0.4),
                Param.fadeIn: .number(0.12), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
            // The core the rings are holding.
            layer("Core", [
                Param.count: .integer(150),
                Param.sprite: .text(BuiltInSprite.flareSoft),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.width: .number(70), Param.height: .number(70),
                Param.velocity: .number(6),
                Param.life: .number(2000), Param.lifeRandom: .number(0.4),
                Param.scaleStart: .number(0.6), Param.scaleEnd: .number(0.9),
                Param.scaleRandom: .number(0.3),
                Param.spin: .number(30),
                Param.color: .color(EffectColor(r: 225, g: 250, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 60, g: 150, b: 255)),
                Param.opacity: .number(0.3),
                Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
        ],
    )
}
