import Foundation

/// The Dandelion pack: seed heads and seeds on the wind.
///
/// Drawn, not lit — none of these are additive. A seed is a thing that blocks
/// light, and white fluff over dark reads fine painted.
///
/// **One wind for the whole pack.** Every seed travels toward `windHeading` —
/// right and a little up — so presets layered on the same scene agree on
/// which way the air moves. A seed blowing left over a meadow swaying right
/// is two weathers at once.
///
/// The textures are shipped unmodified (CC BY-NC-ND — see
/// `Dandelion/CREDITS.md`), so at the small sizes they came in: a single seed
/// is 83px wide, a head 280. Each preset says what it comes out at.
public extension EmitterEffect {
    /// Where the wind blows: an emitter `Direction`, measured from +x
    /// clockwise in a Y-down space — 0 is right, 270 is up — so 345 is right
    /// with a slight rise.
    internal static let windHeading = 345.0

    /// The lean that stands a seed upright: parachute up, stalk hanging.
    ///
    /// The texture lies almost flat — its axis, measured from the alpha, runs
    /// 24° above horizontal with the parachute at the right end — and a real
    /// seed flies with the parachute above it, like the umbrella it is. Turned
    /// −66° it hangs straight; −62° leaves it leaning a touch downwind. The
    /// first version spun them at random and they tumbled sideways and upside
    /// down, which nothing carried by a parachute does.
    internal static let seedUpright = -62.0

    /// A seed's ride on the air, written into its path: a slow bob and a
    /// pendulum rock about its upright lean. Never a spin.
    private static let seedFlutter = EffectPreset.Filter(type: WiggleFilter.descriptor.type, values: [
        WiggleFilter.Param.amount: .number(14),
        WiggleFilter.Param.frequency: .number(0.5),
        WiggleFilter.Param.rotation: .number(8),
    ])

    /// Single seeds adrift on a steady breeze, filling the sky.
    ///
    /// 0.55–0.95 × 83px: 45–80px parachutes. Born all over the frame and
    /// faded in, not marched in from the left edge: from the edge, the field
    /// only reached two thirds of the way across by the middle of the clip
    /// and the rest of the sky sat empty. Level, not rising — with the wind's
    /// own lift and upward gravity on top, twelve seconds carried every seed
    /// into the top corner.
    static let seedDrift = preset("seed-drift", "Seed Drift", "Dandelion seeds adrift on the breeze",
                                  duration: 12_000, pack: "Dandelion", filters: [seedFlutter], [
        Param.count: .integer(40),
        Param.sprite: .text(BuiltInSprite.dandelionSeed),
        Param.shape: .choice(Shape.rectangle.rawValue),
        Param.x: .number(280), Param.y: .number(250),
        Param.width: .number(860), Param.height: .number(400),
        Param.direction: .number(windHeading + 10), Param.spread: .number(6),
        Param.velocity: .number(60), Param.velocityRandom: .number(0.35),
        Param.life: .number(8000), Param.lifeRandom: .number(0.2),
        Param.scaleStart: .number(0.75), Param.scaleEnd: .number(0.75),
        Param.scaleRandom: .number(0.27),
        Param.angle: .number(seedUpright), Param.rotation: .number(6),
        Param.color: .color(.white), Param.colorEnd: .color(EffectColor(r: 240, g: 240, b: 232)),
        Param.opacity: .number(0.9),
        Param.fadeIn: .number(0.18), Param.fadeOut: .number(0.22),
        Param.additive: .toggle(false),
    ])

    /// A gust: a wave of seeds blown in fast, slowing as it passes.
    ///
    /// What makes it a gust and not a breeze is the change in speed: every
    /// seed arrives at once from the left edge, fast, and the drag bleeds the
    /// speed off until they are drifting — the air surging and then letting
    /// go. Single seeds, not the pack's clump texture: a photograph of five
    /// seeds sliding across as one rigid picture was what read as fake.
    /// 0.55–0.95 × 83px, the same seeds as the drift, upright.
    static let seedGust = preset("seed-gust", "Seed Gust", "A wave of seeds blown in fast, slowing as the gust passes",
                                 duration: 6000, pack: "Dandelion", filters: [seedFlutter], [
        Param.count: .integer(45),
        Param.emission: .choice(Emission.burst.rawValue),
        Param.sprite: .text(BuiltInSprite.dandelionSeed),
        Param.shape: .choice(Shape.rectangle.rawValue),
        // Born spread deep off the left edge, so they arrive staggered rather
        // than as one wall marching in — the first version, all born on a
        // thin line at once, entered as a vertical column.
        Param.x: .number(-260), Param.y: .number(250),
        Param.width: .number(300), Param.height: .number(380),
        Param.direction: .number(windHeading + 8), Param.spread: .number(8),
        // Fast in, very unequal, and a light drag: across the stage and still
        // drifting at the end. At 0.25 the drag stopped the lot in a heap a
        // third of the way across — it bites far harder than it reads.
        Param.velocity: .number(520), Param.velocityRandom: .number(0.6),
        Param.drag: .number(0.1),
        Param.gravity: .number(-2),
        Param.life: .number(6000), Param.lifeRandom: .number(0.1),
        Param.scaleStart: .number(0.75), Param.scaleEnd: .number(0.75),
        Param.scaleRandom: .number(0.27),
        Param.angle: .number(seedUpright), Param.rotation: .number(8),
        Param.color: .color(.white), Param.colorEnd: .color(EffectColor(r: 240, g: 240, b: 232)),
        Param.opacity: .number(0.9),
        Param.fadeIn: .number(0.03), Param.fadeOut: .number(0.25),
        Param.additive: .toggle(false),
    ])

    /// One flower of the meadow: a single head, held for the clip, anchored
    /// where its stem meets the ground.
    private static func flower(_ name: String, x: Double, scale: Double, lean: Double) -> EffectPreset.Layer {
        layer(name, [
            Param.count: .integer(1),
            Param.emission: .choice(Emission.burst.rawValue),
            Param.sprite: .text(BuiltInSprite.dandelionTall),
            Param.origin: .choice(Origin.bottomCentre.rawValue),
            Param.angle: .number(lean),
            Param.shape: .choice(Shape.point.rawValue),
            Param.x: .number(x), Param.y: .number(478),
            Param.velocity: .number(0),
            // The whole clip: a flower in a meadow does not vanish when the
            // clip is stretched past its old length.
            Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(1), Param.lifeRandom: .number(0),
            Param.scaleStart: .number(scale), Param.scaleEnd: .number(scale),
            Param.scaleRandom: .number(0),
            Param.color: .color(.white), Param.colorEnd: .color(.white),
            Param.opacity: .number(0.9),
            Param.fadeIn: .number(0.08), Param.fadeOut: .number(0.08),
            Param.additive: .toggle(false),
        ])
    }

    /// Dandelions along the ground, each swaying on its own in the wind.
    ///
    /// **Placed by hand, not scattered.** Five random positions clumped by
    /// chance — four heads pressed into one white thicket with an empty half
    /// stage beside it — and a Grid would line up identical clones. A meadow
    /// is a composition: heights, kinds and gaps chosen so the eye moves
    /// along it.
    ///
    /// **Only the tall head, the one with a straight stem to the ground.** The
    /// drooping one, anchored at its base, lay with its head in the soil and
    /// its stem arching over it — a fallen flower — and the full one's short
    /// crooked stem never stood. Variety comes from height and a fixed lean.
    ///
    /// Anchored `BottomCentre`, so the sway pivots where a stem meets the
    /// ground — centred, a head would rock about its own middle and the stem
    /// would swing through the soil. The sway is a Wiggle on the clip, which
    /// seeds each flower apart, so they lean out of step; rotation only, no
    /// movement — a rooted flower leans, it does not slide. The parent is an
    /// anchor that draws nothing, at the stage centre.
    static let dandelionSway = compound(
        "dandelion-sway", "Dandelion Sway", "Dandelions along the ground, swaying in the wind",
        duration: 10_000,
        [
            Param.count: .integer(1),
            Param.shape: .choice(Shape.point.rawValue),
            Param.x: .number(320), Param.y: .number(240),
            Param.velocity: .number(0),
            Param.opacity: .number(0),
        ],
        pack: "Dandelion",
        layers: [
            // Heights from 0.7 × 268 ≈ 190px to 1.05 × 268 ≈ 280px, each
            // leaning its own few degrees.
            flower("Far Left", x: -50, scale: 0.85, lean: -4),
            flower("Left", x: 120, scale: 1.0, lean: 3),
            flower("Middle", x: 300, scale: 0.7, lean: -2),
            flower("Right", x: 480, scale: 0.92, lean: 5),
            flower("Far Right", x: 670, scale: 1.05, lean: -3),
        ],
        filters: [
            EffectPreset.Filter(type: WiggleFilter.descriptor.type, values: [
                WiggleFilter.Param.amount: .number(0),
                WiggleFilter.Param.frequency: .number(0.5),
                WiggleFilter.Param.rotation: .number(9),
            ]),
        ],
    )

    // ─── Dandelion Blow ──────────────────────────────────────────────────────

    /// Where the blown head sits, shared by the head and the seeds that leave it.
    internal static let blowHead = (x: 230.0, y: 250.0)

    /// A dandelion blown apart: the head bursts into a cloud of seeds that
    /// drift away downwind, and it is gone.
    ///
    /// One puff, not a trickle. The first version let seeds go one by one for
    /// the whole clip while the head stayed full, which made no sense — a head
    /// that keeps all its fluff while shedding it. Now every seed leaves in
    /// the opening moment, thrown fast and braking (a breath is a burst of
    /// air, not a breeze), and the head fades out as they go.
    ///
    /// The seeds are born on the head's fluff — an ellipse the size of the
    /// head — not at a point, and stand upright like every seed in the pack.
    /// They fly with the pack's flutter, which the clip carries. **The parent
    /// is an anchor that draws nothing, at the stage centre**, for the reason
    /// the sunbeam found out: a compound's transform shifts its whole group
    /// by how far the parent sits from the centre, layers included.
    static let dandelionBlow = compound(
        "dandelion-blow", "Dandelion Blow", "A seed head blown apart into a cloud of drifting seeds",
        duration: 7000,
        [
            Param.count: .integer(1),
            Param.shape: .choice(Shape.point.rawValue),
            Param.x: .number(320), Param.y: .number(240),
            Param.velocity: .number(0),
            Param.opacity: .number(0),
        ],
        pack: "Dandelion",
        layers: [
            // The head, fading as its seeds leave: 1.1 × 280 ≈ 310px across,
            // gone by two seconds in.
            layer("Head", [
                Param.count: .integer(1),
                Param.emission: .choice(Emission.burst.rawValue),
                Param.sprite: .text(BuiltInSprite.dandelion),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(blowHead.x), Param.y: .number(blowHead.y),
                Param.velocity: .number(0),
                Param.life: .number(2000),
                Param.scaleStart: .number(1.1), Param.scaleEnd: .number(1.1),
                Param.scaleRandom: .number(0),
                Param.color: .color(.white), Param.colorEnd: .color(.white),
                Param.opacity: .number(0.95),
                Param.fadeIn: .number(0.02), Param.fadeOut: .number(0.75),
                Param.additive: .toggle(false),
            ]),
            // The puff: every seed at once off the fluff, thrown downwind and
            // braking, then drifting. 0.5–0.8 × 83px.
            layer("Seeds", [
                Param.count: .integer(60),
                Param.emission: .choice(Emission.burst.rawValue),
                Param.sprite: .text(BuiltInSprite.dandelionSeed),
                Param.shape: .choice(Shape.ellipse.rawValue),
                Param.x: .number(blowHead.x), Param.y: .number(blowHead.y - 30),
                Param.width: .number(170), Param.height: .number(150),
                Param.direction: .number(windHeading), Param.spread: .number(18),
                // Thrown, braking, then drifting on: at 0.4 the drag stopped
                // the cloud in a clump two seconds in. Lighter, and unequal
                // speeds stretch the cloud out downwind as it goes.
                Param.velocity: .number(230), Param.velocityRandom: .number(0.75),
                Param.drag: .number(0.12),
                Param.gravity: .number(-2),
                // Faded before the right edge: longer, and most of each
                // seed's path ran off the frame — commands nobody sees.
                Param.life: .number(4800), Param.lifeRandom: .number(0.15),
                Param.scaleStart: .number(0.65), Param.scaleEnd: .number(0.65),
                Param.scaleRandom: .number(0.25),
                Param.angle: .number(seedUpright), Param.rotation: .number(8),
                Param.color: .color(.white), Param.colorEnd: .color(EffectColor(r: 240, g: 240, b: 232)),
                Param.opacity: .number(0.9),
                Param.fadeIn: .number(0.02), Param.fadeOut: .number(0.3),
                Param.additive: .toggle(false),
            ]),
        ],
        filters: [seedFlutter],
    )
}
