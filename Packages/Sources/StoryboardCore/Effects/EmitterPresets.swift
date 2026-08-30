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
        lightning, embers, flameJet, slashes, dust,
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
