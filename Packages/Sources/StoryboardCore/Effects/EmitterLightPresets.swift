import Foundation

/// The Light pack: shafts of light drawn by the sunshine textures.
///
/// A shaft of light is **one thing**, not many, so none of these simulate it.
/// Each is a handful of large, still sprites of a texture that already *is*
/// the shaft — the same rule as the orb's beam. What the emitter adds is the
/// overlap: several copies alive at once, each born and faded on its own
/// schedule, so the light breathes instead of hanging there as a picture.
///
/// Three rules every one of them follows, each learned by rendering it:
///
/// - **Anchored `TopCentre`, at the source.** Every brush has its light coming
///   from its top edge. With the origin there the position *is* where the
///   light comes from, and `Angle` pivots the shaft about that point — the way
///   light leans. Centred, a tilted shaft swings its own source sideways.
/// - **Copies identical in angle and size.** The first version tilted and
///   scaled each one a little differently, and rendered it was mush: the brush
///   is fine streaks, and copies that disagree by a few degrees smear them
///   into haze. It is also wrong about the sun, whose rays arrive parallel.
/// - **The light fades in from its source.** The brushes started on a hard
///   edge, and inside the frame that edge read as a stick of light sawn off —
///   so the textures are feathered on every side, the top included (see
///   `Sunshine/CREDITS.md`). The simple presets still hang theirs just above
///   the frame; `sunbeam` puts a glow on it and makes it the source.
///
/// Sizes are against the file: these are 1024px on the long side
/// (`BuiltInSprite.fileSizes`), twice a pack texture. Each preset says what it
/// comes out at.
public extension EmitterEffect {
    /// Broad diagonal rays falling from the top left, breathing slowly.
    ///
    /// 0.62 × 1024 ≈ 635px hanging from a strip just above the frame. Five
    /// alive at a time, cross-fading.
    static let godRays = preset("god-rays", "God Rays", "Broad rays from the top left, slowly breathing",
                                duration: 10_000, pack: "Light", [
        Param.count: .integer(10),
        Param.sprite: .text(BuiltInSprite.godRays),
        Param.origin: .choice(Origin.topCentre.rawValue),
        Param.shape: .choice(Shape.point.rawValue),
        Param.x: .number(250), Param.y: .number(-6),
        Param.velocity: .number(0),
        Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.5), Param.lifeRandom: .number(0.2),
        Param.scaleStart: .number(0.62), Param.scaleEnd: .number(0.62),
        Param.scaleRandom: .number(0),
        Param.color: .color(EffectColor(r: 255, g: 238, b: 200)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 218, b: 160)),
        Param.opacity: .number(0.32),
        Param.fadeIn: .number(0.4), Param.fadeOut: .number(0.45),
        Param.additive: .toggle(true),
    ])

    /// A fan of rays opening downward from above — sun through a gap.
    ///
    /// 0.5 × 1024 = 512px, so the fan reaches past the bottom of the frame.
    static let sunFan = preset("sun-fan", "Sun Fan", "A fan of rays opening down from above",
                               duration: 12_000, pack: "Light", [
        Param.count: .integer(8),
        Param.sprite: .text(BuiltInSprite.sunFan),
        Param.origin: .choice(Origin.topCentre.rawValue),
        Param.shape: .choice(Shape.point.rawValue),
        Param.x: .number(320), Param.y: .number(-6),
        Param.velocity: .number(0),
        Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.5), Param.lifeRandom: .number(0.2),
        Param.scaleStart: .number(0.5), Param.scaleEnd: .number(0.5),
        Param.scaleRandom: .number(0),
        Param.color: .color(EffectColor(r: 255, g: 242, b: 210)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 225, b: 175)),
        Param.opacity: .number(0.32),
        Param.fadeIn: .number(0.4), Param.fadeOut: .number(0.45),
        Param.additive: .toggle(true),
    ])

    /// Thin rays appearing and fading at different places along the top —
    /// light through leaves.
    ///
    /// Unlike the others this one *is* spread out: a ray here and a ray there,
    /// each short-lived, is what reads as a canopy moving. All at one angle,
    /// because sunlight is parallel — rays at different tilts read as sticks.
    /// 0.4 × 1024 ≈ 410px long, hanging from just above the frame.
    static let sunRays = preset("sun-rays", "Sun Rays", "Thin rays flickering in and out, like light through leaves",
                                duration: 8000, pack: "Light", [
        Param.count: .integer(28),
        Param.sprite: .text(BuiltInSprite.sunRay),
        Param.origin: .choice(Origin.topCentre.rawValue),
        Param.shape: .choice(Shape.rectangle.rawValue),
        Param.x: .number(320), Param.y: .number(-10),
        Param.width: .number(640), Param.height: .number(6),
        Param.velocity: .number(0),
        Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.33), Param.lifeRandom: .number(0.35),
        Param.scaleStart: .number(0.4), Param.scaleEnd: .number(0.4),
        Param.scaleRandom: .number(0.12),
        Param.color: .color(EffectColor(r: 255, g: 240, b: 205)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 218, b: 165)),
        Param.opacity: .number(0.28),
        Param.fadeIn: .number(0.35), Param.fadeOut: .number(0.5),
        Param.additive: .toggle(true),
    ])

    /// Three stage lights crossing, dimming between kicks.
    ///
    /// 0.72 × 1024 ≈ 737px, wider than the 4:3 frame: at the stage's height it
    /// was a lit rectangle floating in the middle of the screen. The colour
    /// drifts from a cool white to magenta over each copy's life, so the
    /// overlap carries two tints at once. The Audio Drive is what makes it a
    /// stage: lights that hold still through the music are a picture of one.
    static let stageLights = preset("stage-lights", "Stage Lights", "Crossing beams that flare with the bass",
                                    duration: 8000, pack: "Light", filters: [
        EffectPreset.Filter(type: AudioDriveFilter.descriptor.type, values: [
            AudioDriveFilter.Param.listenTo: .choice(EmitterEffect.AudioBand.bass.rawValue),
            AudioDriveFilter.Param.dim: .number(0.6),
            AudioDriveFilter.Param.smoothing: .number(0.8),
        ]),
    ], [
        Param.count: .integer(8),
        Param.sprite: .text(BuiltInSprite.stageLights),
        Param.origin: .choice(Origin.topCentre.rawValue),
        Param.shape: .choice(Shape.point.rawValue),
        Param.x: .number(320), Param.y: .number(-8),
        Param.velocity: .number(0),
        Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.375), Param.lifeRandom: .number(0.2),
        Param.scaleStart: .number(0.72), Param.scaleEnd: .number(0.72),
        Param.scaleRandom: .number(0),
        Param.color: .color(EffectColor(r: 210, g: 230, b: 255)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 150, b: 225)),
        Param.opacity: .number(0.4),
        Param.fadeIn: .number(0.3), Param.fadeOut: .number(0.4),
        Param.additive: .toggle(true),
    ])

    /// One bright cone, struck on every kick.
    ///
    /// No punch — a spotlight that grows on the beat reads as a lamp swinging
    /// at the camera — only the release, so it flares and settles. 0.45 ×
    /// 1024 ≈ 460px, hanging from just above the frame.
    static let spotlightPulse = preset("spotlight-pulse", "Spotlight Pulse", "A bright cone that flares on every kick",
                                       duration: 8000, pack: "Light", filters: [
        EffectPreset.Filter(type: PulseFilter.descriptor.type, values: [
            PulseFilter.Param.trigger: .choice(PulseFilter.Trigger.bass.rawValue),
            PulseFilter.Param.punch: .number(0),
            PulseFilter.Param.release: .number(0.6),
            PulseFilter.Param.decay: .number(0.5),
        ]),
    ], [
        Param.count: .integer(4),
        Param.sprite: .text(BuiltInSprite.spotCone),
        Param.origin: .choice(Origin.topCentre.rawValue),
        Param.shape: .choice(Shape.point.rawValue),
        Param.x: .number(320), Param.y: .number(-8),
        Param.velocity: .number(0),
        Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.625),
        Param.scaleStart: .number(0.45), Param.scaleEnd: .number(0.45),
        Param.scaleRandom: .number(0),
        Param.color: .color(EffectColor(r: 255, g: 248, b: 230)),
        Param.colorEnd: .color(EffectColor(r: 255, g: 235, b: 200)),
        Param.opacity: .number(0.45),
        Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.3),
        Param.additive: .toggle(true),
    ])

    // ─── Sunbeam ─────────────────────────────────────────────────────────────

    /// Where the sunbeam's light comes from, shared by every layer that has to
    /// sit on it. In the frame, top left: a source you can see is what makes a
    /// beam read as light instead of a smear with no origin.
    internal static let sunbeamSource = (x: 190.0, y: 70.0)

    /// The beam's lean: −28° turns a shaft that hangs straight down toward
    /// the lower right. A sprite's down, (0, 1), turns to (−sin r, cos r).
    internal static let sunbeamAngle = -28.0

    /// The same lean as an emitter `Direction`, which measures from +x
    /// clockwise in a Y-down space: 90 is straight down, and the shaft points
    /// along (−sin r, cos r) = (0.47, 0.88), which is 62° — 90 *plus* the
    /// angle. The first version subtracted it and threw the dust down the
    /// left, outside the beam it was meant to hang in.
    internal static let sunbeamHeading = 90.0 + sunbeamAngle

    /// A beam from a visible light: a bright source with a starburst around
    /// it, the shaft leaning away from it, and dust lit only inside the shaft.
    ///
    /// Built against a reference photograph, after the first version — rays
    /// with their source hidden off the frame — read as a smear with nowhere
    /// to come from. Four things the photograph has that it did not:
    ///
    /// - **A source.** A glow sits exactly on the shaft's top edge and names
    ///   where the light comes from.
    /// - **A starburst.** Short rays all round the source — the fan brush
    ///   itself, small, turned through every angle about its own top, which
    ///   only works because the origin is there.
    /// - **Contrast.** Near white at the source, falling off with distance.
    /// - **Dust in the light.** Motes thrown out along the shaft that brake
    ///   hard and then hang there, so they settle *inside* the beam and
    ///   nowhere else: drag spends a particle's travel in the first fifth of
    ///   its life, and it fades in over that fifth.
    ///
    /// **The parent is an anchor that draws nothing, at the stage centre.**
    ///
    /// A compound's transform carries its whole group, shifting every sprite
    /// by how far the parent sits from the stage centre — layers included, on
    /// top of their own shift. The first version made the shaft the parent, at
    /// the source: every layer was moved to the source once by its own
    /// position and then again by the parent's, and landed 130px left and
    /// 170px up of it — the disc, glow and burst off the frame, streaks and
    /// dust torn away from the shaft, which alone was moved once and sat right.
    /// At the centre the parent shifts nothing, and dragging the clip in the
    /// editor still carries the lot as one. (The vignette learned this first.)
    ///
    /// The probe that rendered the first version fine had evaluated each
    /// layer on its own, which no clip in the app ever does — and a second
    /// fix, reasoned from the code instead of measured, put the anchor at the
    /// source and moved everything twice again. The test that places the
    /// whole compound the way the editor does caught it.
    static let sunbeam = compound(
        "sunbeam", "Sunbeam", "A visible light with a leaning shaft and dust hanging in it",
        duration: 10_000,
        [
            Param.count: .integer(1),
            Param.shape: .choice(Shape.point.rawValue),
            Param.x: .number(320), Param.y: .number(240),
            Param.velocity: .number(0),
            Param.opacity: .number(0),
        ],
        pack: "Light",
        layers: [
            // The body: the soft cone, 0.62 × 1024 ≈ 635px down the lean.
            layer("Body", [
                Param.count: .integer(6),
                Param.sprite: .text(BuiltInSprite.spotCone),
                Param.origin: .choice(Origin.topCentre.rawValue),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(sunbeamSource.x), Param.y: .number(sunbeamSource.y),
                Param.angle: .number(sunbeamAngle),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.5), Param.lifeRandom: .number(0.2),
                Param.scaleStart: .number(0.62), Param.scaleEnd: .number(0.62),
                Param.scaleRandom: .number(0),
                Param.color: .color(EffectColor(r: 255, g: 245, b: 220)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 226, b: 175)),
                Param.opacity: .number(0.3),
                Param.fadeIn: .number(0.4), Param.fadeOut: .number(0.45),
                Param.additive: .toggle(true),
            ]),
            // The streaks inside the body — the fan brush on the same source
            // and lean, so the shaft has structure instead of a smooth wedge.
            layer("Streaks", [
                Param.count: .integer(6),
                Param.sprite: .text(BuiltInSprite.sunFan),
                Param.origin: .choice(Origin.topCentre.rawValue),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(sunbeamSource.x), Param.y: .number(sunbeamSource.y),
                Param.angle: .number(sunbeamAngle),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.5), Param.lifeRandom: .number(0.2),
                Param.scaleStart: .number(0.6), Param.scaleEnd: .number(0.6),
                Param.scaleRandom: .number(0),
                Param.color: .color(EffectColor(r: 255, g: 240, b: 205)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 220, b: 165)),
                Param.opacity: .number(0.24),
                Param.fadeIn: .number(0.4), Param.fadeOut: .number(0.45),
                Param.additive: .toggle(true),
            ]),
            // The starburst: the fan brush at 0.22 × 1024 ≈ 225px, turned
            // through every angle about its top — which is the source — so
            // short rays leave it in all directions. The one place a random
            // tilt is right: a burst is many directions by definition.
            layer("Burst", [
                Param.count: .integer(30),
                Param.sprite: .text(BuiltInSprite.sunFan),
                Param.origin: .choice(Origin.topCentre.rawValue),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(sunbeamSource.x), Param.y: .number(sunbeamSource.y),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.4), Param.lifeRandom: .number(0.3),
                Param.scaleStart: .number(0.22), Param.scaleEnd: .number(0.22),
                Param.scaleRandom: .number(0.3),
                Param.rotation: .number(360),
                Param.color: .color(EffectColor(r: 255, g: 245, b: 215)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 225, b: 170)),
                Param.opacity: .number(0.32),
                Param.fadeIn: .number(0.35), Param.fadeOut: .number(0.45),
                Param.additive: .toggle(true),
            ]),
            // The halo round the source: the 64px glow at 3.2 ≈ 205px.
            layer("Glow", [
                Param.count: .integer(3),
                Param.sprite: .text(BuiltInSprite.glow),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(sunbeamSource.x), Param.y: .number(sunbeamSource.y),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.6),
                Param.scaleStart: .number(3.2), Param.scaleEnd: .number(3.2),
                Param.scaleRandom: .number(0),
                Param.color: .color(EffectColor(r: 255, g: 238, b: 200)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 228, b: 180)),
                Param.opacity: .number(0.6),
                Param.fadeIn: .number(0.3), Param.fadeOut: .number(0.3),
                Param.additive: .toggle(true),
            ]),
            // The source itself: a near-white soft disc, 1.1 × 64 ≈ 70px. The
            // brushes fade in from their top edge, so it does not have to hide
            // a cut — only to be the brightest thing in the frame.
            layer("Source", [
                Param.count: .integer(3),
                Param.sprite: .text(BuiltInSprite.soft),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(sunbeamSource.x), Param.y: .number(sunbeamSource.y),
                Param.velocity: .number(0),
                Param.lifeMode: .choice(LifeMode.clip.rawValue), Param.lifeFraction: .number(0.6),
                Param.scaleStart: .number(1.1), Param.scaleEnd: .number(1.1),
                Param.scaleRandom: .number(0),
                Param.color: .color(EffectColor(r: 255, g: 252, b: 240)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 250, b: 235)),
                Param.opacity: .number(0.95),
                Param.fadeIn: .number(0.2), Param.fadeOut: .number(0.2),
                Param.additive: .toggle(true),
            ]),
            // Dust hanging in the light: thrown down the lean within the
            // cone's spread — ±22°, since `Spread` is a half-angle and the
            // cone is about ±25° across (at 34 a quarter of it hung in the
            // dark beside the beam), braked hard so each one settles where it lands,
            // and faded in over the braking — what the eye sees is motes
            // suspended along the shaft, never a stream leaving the source.
            layer("Dust", [
                Param.count: .integer(320),
                Param.sprite: .text(BuiltInSprite.glow),
                Param.shape: .choice(Shape.point.rawValue),
                Param.x: .number(sunbeamSource.x), Param.y: .number(sunbeamSource.y),
                Param.direction: .number(sunbeamHeading), Param.spread: .number(22),
                // Reach is what makes it dust: the shaft is ~600px long, and
                // motes that only got a third of the way down read as sparks
                // leaving the source. Near-full velocity randomness spreads
                // where each one settles from the source to the far end.
                Param.velocity: .number(420), Param.velocityRandom: .number(0.95),
                Param.drag: .number(0.3),
                // A slow rise once settled: dust floats on the warm air in a
                // sunbeam rather than hanging dead still.
                Param.gravity: .number(-3),
                Param.life: .number(7000), Param.lifeRandom: .number(0.4),
                // Sizes all over the place, as real motes are: most are
                // pinpricks, a few are out-of-focus specks.
                Param.scaleStart: .number(0.05), Param.scaleEnd: .number(0.04),
                Param.scaleRandom: .number(0.8),
                Param.color: .color(EffectColor(r: 255, g: 245, b: 220)),
                Param.colorEnd: .color(EffectColor(r: 255, g: 228, b: 185)),
                Param.opacity: .number(0.75),
                Param.fadeIn: .number(0.25), Param.fadeOut: .number(0.35),
                Param.additive: .toggle(true),
            ]),
        ],
    )
}
