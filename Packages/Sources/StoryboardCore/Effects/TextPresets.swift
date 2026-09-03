import Foundation

public extension TextEffect {
    /// The text effect's preset library.
    ///
    /// Each one is a named move rather than a set of numbers that happened to
    /// look right — a typewriter types, a drop falls and lands, a shockwave
    /// arrives all at once and slams. Naming the move is what makes a preset a
    /// starting point instead of a black box: you know what to reach for, and
    /// you know which number to turn when it is nearly right.
    static let presets: [EffectPreset] = [
        typewriter, fadeUp, drop, popIn, sweep, scatter,
        shockwave, unfold, cascade, wave, glitch, revealCentre,
        driftApart, burst,
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

    // ─── Arrivals ────────────────────────────────────────────────────────────

    /// Characters appearing one at a time, with no movement at all.
    ///
    /// The fade is short rather than absent: a glyph snapping on at full
    /// opacity flickers, and osu! has no way to say "appear" other than a fade
    /// too quick to read as one.
    static let typewriter = preset(
        "typewriter", "Typewriter", "Characters appear one at a time", [
            Param.stagger: .number(70),
            Param.fadeIn: .number(40),
            Param.fadeOut: .number(200),
            Param.easing: .choice("Linear"),
        ],
    )

    /// The workhorse: letters rising into place as they fade in.
    static let fadeUp = preset(
        "fade-up", "Fade Up", "Letters rise gently into place", [
            Param.stagger: .number(45),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(400),
            Param.riseFrom: .number(30),
            Param.easing: .choice("Expo"),
        ],
    )

    /// Falling from above and landing, weight and all.
    static let drop = preset(
        "drop", "Drop", "Letters fall in and land", [
            Param.stagger: .number(60),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(300),
            Param.riseFrom: .number(-120),
            Param.easing: .choice("Bounce"),
        ],
    )

    /// Overshooting its size and settling — the move that reads as playful.
    static let popIn = preset(
        "pop-in", "Pop In", "Letters spring up past their size and settle", [
            Param.stagger: .number(50),
            Param.fadeIn: .number(350),
            Param.fadeOut: .number(250),
            Param.scaleFrom: .number(0.4),
            Param.easing: .choice("Back"),
            Param.exit: .choice("Shrink"),
        ],
    )

    /// Sliding in from the side, which is what a lower third does.
    static let sweep = preset(
        "sweep", "Sweep", "Letters slide in from the left", [
            Param.stagger: .number(30),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(300),
            Param.driftFrom: .number(-180),
            Param.easing: .choice("Expo"),
        ],
    )

    /// Arriving from every direction at once.
    ///
    /// Random order and a diagonal offset together: either alone reads as a
    /// mistake, and the two together read as assembly.
    static let scatter = preset(
        "scatter", "Scatter", "Letters converge from all directions", [
            Param.stagger: .number(35),
            Param.staggerFrom: .choice("Random"),
            Param.fadeIn: .number(500),
            Param.fadeOut: .number(300),
            Param.riseFrom: .number(90),
            Param.driftFrom: .number(-140),
            Param.scaleFrom: .number(0.6),
            Param.spinFrom: .number(-45),
            Param.easing: .choice("Expo"),
        ],
    )

    // ─── Statements ──────────────────────────────────────────────────────────

    /// Everything at once, large and settling — a title, not a caption.
    static let shockwave = preset(
        "text-shockwave", "Shockwave", "The whole line lands at once", duration: 2500, [
            Param.stagger: .number(0),
            Param.fadeIn: .number(250),
            Param.fadeOut: .number(400),
            Param.scaleFrom: .number(2.4),
            Param.easing: .choice("Expo"),
            Param.exit: .choice("Grow"),
        ],
    )

    /// Turning flat into view, as though the line had been edge-on.
    ///
    /// Approximated with a vertical squash, since the format has no
    /// perspective: the glyph is scaled from nothing on one axis, which reads
    /// as a card turning even without depth.
    static let unfold = preset(
        "unfold", "Unfold", "Letters open out from flat", [
            Param.stagger: .number(55),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(300),
            Param.scaleFrom: .number(0.05),
            Param.easing: .choice("Back"),
        ],
    )

    /// A long, slow arrival — for a line meant to be read rather than noticed.
    static let cascade = preset(
        "cascade", "Cascade", "A slow wave of letters from the left", duration: 6000, [
            Param.stagger: .number(110),
            Param.fadeIn: .number(700),
            Param.fadeOut: .number(500),
            Param.riseFrom: .number(24),
            Param.easing: .choice("Ease Out"),
        ],
    )

    // ─── Character ───────────────────────────────────────────────────────────

    /// Springing in with a wobble, which is what elastic is for.
    static let wave = preset(
        "wave", "Wave", "Letters spring in with a wobble", [
            Param.stagger: .number(60),
            Param.fadeIn: .number(600),
            Param.fadeOut: .number(300),
            Param.riseFrom: .number(40),
            Param.easing: .choice("Elastic"),
        ],
    )

    /// Snapping into place out of order, hard and fast.
    ///
    /// No easing curve and a very short fade: the point is that nothing eases.
    /// Softening any part of it turns a glitch into a shuffle.
    static let glitch = preset(
        "glitch", "Glitch", "Letters snap in out of order", duration: 2000, [
            Param.stagger: .number(25),
            Param.staggerFrom: .choice("Random"),
            Param.fadeIn: .number(30),
            Param.fadeOut: .number(80),
            Param.driftFrom: .number(14),
            Param.easing: .choice("Linear"),
        ],
    )

    /// The credit-roll move: arrives, drifts as it holds, then blows apart.
    ///
    /// The three phases are the point. A line that appears, sits perfectly
    /// still, and fades is three separate moments; giving it somewhere to go
    /// while it is up, and somewhere to go when it leaves, makes them one shot.
    static let burst = preset(
        "burst", "Burst", "Drifts as it holds, then scatters outward", duration: 5000, [
            Param.stagger: .number(40),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(900),
            Param.riseFrom: .number(20),
            Param.easing: .choice("Expo"),
            Param.driftY: .number(-40),
            Param.exit: .choice("Explode"),
            Param.exitForce: .number(320),
        ],
    )

    /// Letters wandering off in their own directions, slowly.
    ///
    /// The same machinery as `burst` with the force turned down and the
    /// headings unpicked — smoke rather than shrapnel.
    static let driftApart = preset(
        "drift-apart", "Drift Apart", "Letters wander off in their own directions",
        duration: 6000, [
            Param.stagger: .number(80),
            Param.fadeIn: .number(700),
            Param.fadeOut: .number(1600),
            Param.easing: .choice("Ease Out"),
            Param.driftX: .number(30),
            Param.exit: .choice("Drift"),
            Param.exitForce: .number(90),
        ],
    )

    /// Opening outward from the middle of the line.
    static let revealCentre = preset(
        "reveal-centre", "Reveal", "The line opens from its centre outward", [
            Param.stagger: .number(60),
            Param.staggerFrom: .choice("Centre"),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(350),
            Param.scaleFrom: .number(0.5),
            Param.easing: .choice("Back"),
        ],
    )
}
