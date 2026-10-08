import Foundation

/// The Hi-Tech pack: sci-fi interface pieces, after Particle Illusion's
/// loaders, spinners and lock-ons.
///
/// Built from the HUD vocabulary `BuiltInTextures` draws in code — segmented
/// rings, arcs, dashes, ticks, brackets — rather than from a brush pack: they
/// are pure geometry, so code draws them sharp at any size, and a paid pack's
/// files could not ship inside the app anyway.
///
/// **What makes these read as machinery is counter-rotation.** One ring
/// turning is a picture spinning; rings turning against each other at
/// different speeds read as parts of a mechanism, the same trick the portal
/// already uses. Every ring is one sprite held for the clip and turned by
/// `Spin` — the HUD shapes are centred on their canvas, so a spinning one
/// turns in place.
///
/// Additive, and with a Glow on the clip: an interface hanging in the air is
/// light, and the halo is what makes thin lines read as lit rather than drawn.
///
/// **Every compound's parent is an anchor that draws nothing, at the stage
/// centre** — the sunbeam's lesson: a compound's transform shifts its whole
/// group by how far the parent sits from the centre, layers included.
public extension EmitterEffect {
    /// The clip-wide halo every preset in the pack carries.
    private static let hudGlow = EffectPreset.Filter(type: GlowFilter.descriptor.type, values: [
        GlowFilter.Param.radius: .number(10),
        GlowFilter.Param.intensity: .number(0.9),
    ])

    private static let hudAnchor: [String: EffectValue] = [
        Param.count: .integer(1),
        Param.shape: .choice(Shape.point.rawValue),
        Param.x: .number(320), Param.y: .number(240),
        Param.velocity: .number(0),
        Param.opacity: .number(0),
    ]

    /// One ring of an interface: a single sprite, held for the whole clip and
    /// turned by `spin` (degrees a second; negative turns the other way).
    /// Scale is against 512: 0.6 is a ring ~300px across.
    private static func hudRing(
        _ name: String, _ sprite: String, scale: Double, spin: Double,
        colour: EffectColor, opacity: Double,
        x: Double = 320, y: Double = 240, scaleEnd: Double? = nil, angle: Double = 0,
    ) -> EffectPreset.Layer {
        layer(name, [
            Param.count: .integer(1),
            Param.emission: .choice(Emission.burst.rawValue),
            Param.sprite: .text(sprite),
            Param.shape: .choice(Shape.point.rawValue),
            Param.x: .number(x), Param.y: .number(y),
            Param.velocity: .number(0),
            // The whole clip, however long it is stretched — a ring is held,
            // not a particle with a lifespan; in milliseconds it died at the
            // clip's old length. Every ring alike: the default life randomness
            // gave each bracket of a lock its own life, and since scale runs
            // over a life, four brackets meant to close together sat at four
            // different sizes.
            Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(1), Param.lifeRandom: .number(0),
            Param.scaleStart: .number(scale), Param.scaleEnd: .number(scaleEnd ?? scale),
            Param.scaleRandom: .number(0),
            Param.angle: .number(angle), Param.spin: .number(spin),
            Param.color: .color(colour), Param.colorEnd: .color(colour),
            Param.opacity: .number(opacity),
            Param.fadeIn: .number(0.06), Param.fadeOut: .number(0.1),
            Param.additive: .toggle(true),
        ])
    }

    /// The bright heart a mechanism turns around: the glow texture, held.
    private static func hudCore(_ colour: EffectColor, scale: Double, opacity: Double) -> EffectPreset.Layer {
        layer("Core", [
            Param.count: .integer(1),
            Param.emission: .choice(Emission.burst.rawValue),
            Param.sprite: .text(BuiltInSprite.glow),
            Param.shape: .choice(Shape.point.rawValue),
            Param.x: .number(320), Param.y: .number(240),
            Param.velocity: .number(0),
            Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(1), Param.lifeRandom: .number(0),
            Param.scaleStart: .number(scale), Param.scaleEnd: .number(scale),
            Param.scaleRandom: .number(0),
            Param.color: .color(colour), Param.colorEnd: .color(colour),
            Param.opacity: .number(opacity),
            Param.fadeIn: .number(0.08), Param.fadeOut: .number(0.1),
            Param.additive: .toggle(true),
        ])
    }

    // ─── Loader ──────────────────────────────────────────────────────────────

    /// A cyan loader: four rings turning against each other around a glowing
    /// core, with energy running round the outside.
    ///
    /// Speeds rise toward the middle — the dial crawls, the inner arcs race —
    /// because that is how nested parts of a real mechanism look, and evenly
    /// matched speeds read as one rotating picture. Directions alternate ring
    /// by ring. The energy is particles leaving a ring *along* it (`Swirl`
    /// 90), short-lived, so what reads is a current running round the rim.
    static let hudLoader = compound(
        "hud-loader", "HUD Loader", "Rings turning against each other around a glowing core",
        duration: 8000, hudAnchor, pack: "Hi-Tech",
        layers: [
            // 0.80 × 512 ≈ 410px dial, crawling backward.
            hudRing("Dial", BuiltInSprite.hudTicks, scale: 0.8, spin: -12,
                    colour: EffectColor(r: 90, g: 220, b: 255), opacity: 0.55),
            hudRing("Segments", BuiltInSprite.hudSegments, scale: 0.62, spin: 40,
                    colour: EffectColor(r: 90, g: 230, b: 255), opacity: 0.85),
            hudRing("Dashes", BuiltInSprite.hudDashes, scale: 0.5, spin: -75,
                    colour: EffectColor(r: 160, g: 240, b: 255), opacity: 0.7),
            hudRing("Arcs", BuiltInSprite.hudArcs, scale: 0.38, spin: 140,
                    colour: EffectColor(r: 200, g: 255, b: 255), opacity: 0.9),
            // 3.6 × 64 ≈ 230px of light filling the inner rings — a speck at
            // the centre read as a lamp, not a power source.
            hudCore(EffectColor(r: 120, g: 230, b: 255), scale: 3.6, opacity: 0.9),
            layer("Current", [
                Param.count: .integer(800),
                Param.sprite: .text(BuiltInSprite.soft),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.x: .number(320), Param.y: .number(240),
                Param.width: .number(360), Param.height: .number(360),
                Param.radial: .toggle(true), Param.swirl: .number(90),
                Param.direction: .number(270), Param.spread: .number(0),
                Param.velocity: .number(140), Param.velocityRandom: .number(0.2),
                Param.life: .number(500), Param.lifeRandom: .number(0.3),
                Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.03),
                Param.scaleRandom: .number(0.3),
                Param.color: .color(EffectColor(r: 210, g: 255, b: 255)),
                Param.colorEnd: .color(EffectColor(r: 60, g: 180, b: 255)),
                Param.opacity: .number(0.8),
                Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
        ],
        filters: [hudGlow],
    )

    // ─── Target Lock ─────────────────────────────────────────────────────────

    /// A lock-on: four brackets closing on a red target while its rings turn.
    ///
    /// The brackets are one shape turned a quarter round each (`Angle`), and
    /// they all spin at the same rate, so they stay a square while the square
    /// turns. Closing in is their scale shrinking over the clip — the one
    /// motion here that goes somewhere, which is what makes it read as
    /// acquiring rather than idling.
    static let hudTargetLock = compound(
        "hud-target-lock", "HUD Target Lock", "Brackets closing on a target as its rings turn",
        duration: 6000, hudAnchor, pack: "Hi-Tech",
        layers: [
            // 0.95 → 0.6 × 512: brackets from ~490px across closing to ~310.
            hudRing("Bracket Top", BuiltInSprite.hudBracket, scale: 0.95, spin: 18,
                    colour: EffectColor(r: 255, g: 215, b: 60), opacity: 0.95,
                    scaleEnd: 0.6, angle: 0),
            hudRing("Bracket Right", BuiltInSprite.hudBracket, scale: 0.95, spin: 18,
                    colour: EffectColor(r: 255, g: 215, b: 60), opacity: 0.95,
                    scaleEnd: 0.6, angle: 90),
            hudRing("Bracket Bottom", BuiltInSprite.hudBracket, scale: 0.95, spin: 18,
                    colour: EffectColor(r: 255, g: 215, b: 60), opacity: 0.95,
                    scaleEnd: 0.6, angle: 180),
            hudRing("Bracket Left", BuiltInSprite.hudBracket, scale: 0.95, spin: 18,
                    colour: EffectColor(r: 255, g: 215, b: 60), opacity: 0.95,
                    // −90, not 270: `Angle` runs −180…180 and coerce clamps,
                    // so 270 came out 180 and sat on top of the bottom one.
                    scaleEnd: 0.6, angle: -90),
            hudRing("Segments", BuiltInSprite.hudSegments, scale: 0.46, spin: -35,
                    colour: EffectColor(r: 255, g: 70, b: 50), opacity: 0.85),
            hudRing("Arc", BuiltInSprite.hudArc, scale: 0.3, spin: 110,
                    colour: EffectColor(r: 255, g: 150, b: 40), opacity: 0.9),
            hudCore(EffectColor(r: 255, g: 80, b: 50), scale: 1.6, opacity: 0.8),
        ],
        filters: [hudGlow],
    )

    // ─── Data Spinner ────────────────────────────────────────────────────────

    /// A green holographic disc seen at an angle, with a column of light
    /// rising out of it.
    ///
    /// A single sprite cannot be a tilted spinning disc — squashed and then
    /// turned, it spins as an oval. So the rings are particles running round
    /// a tilted ellipse (`Tilt` foreshortens it and orders it back to front),
    /// two of them in opposite directions; what reads as rotation is the
    /// procession, the same way the arc reactor's rings do it.
    static let hudDataSpinner = compound(
        "hud-data-spinner", "HUD Data Spinner", "A tilted holographic disc with light rising from it",
        duration: 6000, hudAnchor, pack: "Hi-Tech",
        layers: [
            layer("Outer Ring", [
                // Alive at once is what draws the ring: count × life ÷ clip.
                // 900 × 450 ÷ 6000 left ~70 dashes on the whole rim, which
                // read as scattered sparks. Bought with life, not count —
                // life is free and count costs a sprite each, and a compound
                // has 2000 to spend: this is ~200 alive from 1100.
                Param.count: .integer(1100),
                Param.sprite: .text(BuiltInSprite.streak),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.x: .number(320), Param.y: .number(300),
                Param.width: .number(360), Param.height: .number(360),
                Param.tilt: .number(72),
                Param.radial: .toggle(true), Param.swirl: .number(90),
                Param.direction: .number(270), Param.spread: .number(0),
                // Short hops: a tangent is a straight line and the ring is
                // curved, so a long run leaves the ellipse.
                Param.velocity: .number(70),
                Param.life: .number(1100), Param.lifeRandom: .number(0.2),
                Param.alignToMotion: .toggle(true),
                // Soft-ended streaks (128px): 0.16 × 128 ≈ 20px dashes along
                // the run. Hard little squares read as scattered debris, not
                // as a ring of light.
                Param.scaleStart: .number(0.16), Param.scaleEnd: .number(0.1),
                Param.stretch: .number(1.6),
                Param.color: .color(EffectColor(r: 190, g: 255, b: 150)),
                Param.colorEnd: .color(EffectColor(r: 70, g: 200, b: 90)),
                Param.opacity: .number(0.7),
                Param.fadeIn: .number(0.2), Param.fadeOut: .number(0.4),
                Param.additive: .toggle(true),
            ]),
            layer("Inner Ring", [
                Param.count: .integer(700),
                Param.sprite: .text(BuiltInSprite.streak),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.x: .number(320), Param.y: .number(300),
                Param.width: .number(210), Param.height: .number(210),
                Param.tilt: .number(72),
                Param.radial: .toggle(true), Param.swirl: .number(-90),
                Param.direction: .number(270), Param.spread: .number(0),
                Param.velocity: .number(50),
                Param.life: .number(1100), Param.lifeRandom: .number(0.2),
                Param.alignToMotion: .toggle(true),
                Param.scaleStart: .number(0.13), Param.scaleEnd: .number(0.08),
                Param.stretch: .number(1.5),
                Param.color: .color(EffectColor(r: 220, g: 255, b: 190)),
                Param.colorEnd: .color(EffectColor(r: 90, g: 220, b: 110)),
                Param.opacity: .number(0.75),
                Param.fadeIn: .number(0.2), Param.fadeOut: .number(0.4),
                Param.additive: .toggle(true),
            ]),
            // The disc's glow, flattened by stretch to lie in the ring's plane:
            // 3.6 × 64 ≈ 230px wide, a third as tall.
            layer("Disc", [
                Param.count: .integer(2),
                Param.emission: .choice(Emission.burst.rawValue),
                Param.sprite: .text(BuiltInSprite.glow),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(320), Param.y: .number(300),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(1),
                Param.scaleStart: .number(3.6), Param.scaleEnd: .number(3.6),
                Param.scaleRandom: .number(0),
                Param.stretch: .number(0.3),
                Param.color: .color(EffectColor(r: 150, g: 255, b: 120)),
                Param.colorEnd: .color(EffectColor(r: 150, g: 255, b: 120)),
                Param.opacity: .number(0.6),
                Param.fadeIn: .number(0.08), Param.fadeOut: .number(0.1),
                Param.additive: .toggle(true),
            ]),
            // The projection rising out of it: the Sun Fan brush turned
            // upside down (`Angle` 180) and hung from its source at the disc
            // (`TopCentre`), so the rays open upward like a hologram beam.
            // 0.34 × 1024 ≈ 350px tall. A beam texture stood on the disc came
            // out a hairline floating above it.
            layer("Projection", [
                Param.count: .integer(4),
                Param.sprite: .text(BuiltInSprite.sunFan),
                Param.origin: .choice(Origin.topCentre.rawValue),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(320), Param.y: .number(300),
                Param.angle: .number(180),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.5), Param.lifeRandom: .number(0.2),
                Param.scaleStart: .number(0.34), Param.scaleEnd: .number(0.34),
                Param.scaleRandom: .number(0),
                Param.color: .color(EffectColor(r: 170, g: 255, b: 140)),
                Param.colorEnd: .color(EffectColor(r: 90, g: 220, b: 100)),
                Param.opacity: .number(0.35),
                Param.fadeIn: .number(0.3), Param.fadeOut: .number(0.4),
                Param.additive: .toggle(true),
            ]),
        ],
        filters: [hudGlow],
    )

    // ─── Warp Core ───────────────────────────────────────────────────────────

    /// A golden energy core: a banded sphere inside turning dials, with
    /// streaks being drawn into it.
    ///
    /// The streaks fly *inward* (`Radial` with Direction 90), lived exactly as
    /// long as it takes to arrive, so every one ends at the core — the same
    /// construction as Converge. Something feeding the core is what makes it
    /// read as a power source rather than a bauble.
    static let hudWarpCore = compound(
        "hud-warp-core", "HUD Warp Core", "A golden energy core drawing streaks into it",
        duration: 6000, hudAnchor, pack: "Hi-Tech",
        layers: [
            hudRing("Dial", BuiltInSprite.hudTicks, scale: 0.72, spin: 14,
                    colour: EffectColor(r: 255, g: 200, b: 90), opacity: 0.6),
            hudRing("Arcs", BuiltInSprite.hudArcs, scale: 0.56, spin: -55,
                    colour: EffectColor(r: 255, g: 150, b: 50), opacity: 0.8),
            hudRing("Dashes", BuiltInSprite.hudDashes, scale: 0.44, spin: 90,
                    colour: EffectColor(r: 255, g: 230, b: 150), opacity: 0.6),
            layer("Sphere", [
                Param.count: .integer(800),
                Param.sprite: .text(BuiltInSprite.soft),
                Param.shape: .choice(Shape.sphere.rawValue),
                Param.x: .number(320), Param.y: .number(240),
                Param.width: .number(180), Param.height: .number(180),
                Param.bands: .integer(7), Param.tilt: .number(55),
                Param.velocity: .number(8), Param.velocityRandom: .number(0.6),
                Param.life: .number(1600), Param.lifeRandom: .number(0.3),
                Param.scaleStart: .number(0.12), Param.scaleEnd: .number(0.04),
                Param.scaleRandom: .number(0.3),
                Param.color: .color(EffectColor(r: 255, g: 240, b: 190)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 140, b: 40)),
                Param.opacity: .number(0.45),
                Param.fadeIn: .number(0.15), Param.fadeOut: .number(0.5),
                Param.additive: .toggle(true),
            ]),
            // Drawn in from a ring 260px out at 260px a second for one second,
            // so each streak ends on the core.
            layer("Inflow", [
                Param.count: .integer(160),
                Param.sprite: .text(BuiltInSprite.streak),
                Param.shape: .choice(Shape.ring.rawValue),
                Param.x: .number(320), Param.y: .number(240),
                Param.width: .number(520), Param.height: .number(520),
                Param.radial: .toggle(true), Param.direction: .number(90), Param.spread: .number(0),
                Param.velocity: .number(240), Param.velocityRandom: .number(0),
                Param.life: .number(1000), Param.lifeRandom: .number(0),
                Param.alignToMotion: .toggle(true),
                Param.scaleStart: .number(0.35), Param.scaleEnd: .number(0.15),
                Param.stretch: .number(2.5),
                Param.color: .color(EffectColor(r: 255, g: 230, b: 160)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 170, b: 60)),
                Param.opacity: .number(0.6),
                Param.fadeIn: .number(0.2), Param.fadeOut: .number(0.2),
                Param.additive: .toggle(true),
            ]),
            hudCore(EffectColor(r: 255, g: 210, b: 120), scale: 2.2, opacity: 0.9),
        ],
        filters: [hudGlow],
    )
}
