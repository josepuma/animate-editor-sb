import Foundation

public extension TextEffect {
    /// The presets the hold, the parametric exits and the colour modes make
    /// possible: text that keeps moving while it is up, that leaves on its own
    /// schedule, that lights up as it is sung.
    ///
    /// Only numbers on the one text effect, like every preset before them, and
    /// none sets content — text, font, size or the base colour — so swapping
    /// presets never takes the author's words or colour away. A colour preset
    /// sets only the *second* colour: what the words change to, not what they
    /// are.
    ///
    /// A hold costs steps: the five that move while holding may write up to
    /// 64 commands a glyph (48 of them the hold); every other one stays at ten.
    static let motionPresets: [EffectPreset] = [
        karaokeSweep, softFloat, echoLines, breathing, shakeHold,
        glitchIn, scanLine, zigzagWave, gradientTitle, mirrorOut,
    ]

    /// Words lighting up one after another as they are sung.
    ///
    /// Word, not character: a karaoke line lights by the word, and a sweep a
    /// letter at a time reads as a progress bar.
    static let karaokeSweep = preset(
        "karaoke-sweep", "Karaoke Sweep", "Words light up one after another", duration: 5000, [
            Param.unit: .choice("Word"),
            Param.fadeIn: .number(200),
            Param.fadeOut: .number(300),
            Param.colourMode: .choice("Highlight"),
            Param.colour2: .color(EffectColor(r: 255, g: 220, b: 90)),
            Param.sweepStart: .number(10),
            Param.sweepLength: .number(70),
            Param.sweepEdge: .number(120),
        ],
    )

    /// Letters rising in and then drifting in a slow figure while they hold.
    static let softFloat = preset(
        "soft-float", "Soft Float", "Letters float gently while they hold", duration: 5000, [
            Param.stagger: .number(40),
            Param.fadeIn: .number(500),
            Param.fadeOut: .number(400),
            Param.riseFrom: .number(20),
            Param.easing: .choice("Ease Out"),
            Param.holdMotion: .choice("Float"),
            Param.holdAmount: .number(6),
            Param.holdSpeed: .number(0.4),
            Param.holdPhase: .number(50),
        ],
    )

    /// Lines stacking in from the left and peeling off from the bottom.
    ///
    /// Reverse is last in, first out: the line that arrived last leaves
    /// first, each sliding back out the way it came on the mirrored curve —
    /// the stack unwinds instead of the first line vanishing out from under
    /// the rest.
    static let echoLines = preset(
        "echo-lines", "Echo Lines", "Lines stack in and peel off, last in first out", [
            Param.unit: .choice("Line"),
            Param.stagger: .number(300),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(400),
            Param.driftFrom: .number(-120),
            Param.easing: .choice("Expo"),
            Param.exit: .choice("Mirror In"),
            Param.exitStagger: .number(300),
            Param.exitOrder: .choice("Reverse"),
        ],
    )

    /// The line swelling and settling, each letter a beat behind the last.
    static let breathing = preset(
        "breathing", "Breathing", "Letters swell and settle while they hold", duration: 5000, [
            Param.stagger: .number(30),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(400),
            Param.holdMotion: .choice("Breathe"),
            Param.holdBreathe: .number(8),
            Param.holdSpeed: .number(0.5),
            Param.holdPhase: .number(30),
        ],
    )

    /// Words slamming in big and trembling with the impact while they hold.
    ///
    /// Word, so a word shakes as one: letters shaking apart would read as the
    /// word breaking, not as it being hit.
    static let shakeHold = preset(
        "shake-hold", "Shake Hold", "Words slam in and tremble while they hold", [
            Param.unit: .choice("Word"),
            Param.stagger: .number(150),
            Param.fadeIn: .number(150),
            Param.fadeOut: .number(250),
            Param.scaleFrom: .number(1.6),
            Param.easing: .choice("Expo"),
            Param.holdMotion: .choice("Shake"),
            Param.holdAmount: .number(3),
            Param.holdSpeed: .number(1.5),
        ],
    )

    /// Snapping in out of order and jumping now and then while it holds.
    ///
    /// Jitter, not Shake: a glitch jumps between places and holds still in
    /// between, where a shake never rests.
    static let glitchIn = preset(
        "glitch-in", "Glitch In", "Letters snap in out of order and keep glitching", duration: 3000, [
            Param.staggerFrom: .choice("Random"),
            Param.stagger: .number(25),
            Param.fadeIn: .number(40),
            Param.fadeOut: .number(120),
            Param.driftFrom: .number(10),
            Param.easing: .choice("Linear"),
            Param.holdMotion: .choice("Jitter"),
            Param.holdAmount: .number(6),
            Param.holdSpeed: .number(1),
        ],
    )

    /// A flash running down the text a line at a time, and back.
    static let scanLine = preset(
        "scan-line", "Scan Line", "A flash runs down the lines", [
            Param.unit: .choice("Line"),
            Param.stagger: .number(200),
            Param.fadeIn: .number(200),
            Param.fadeOut: .number(300),
            Param.colourMode: .choice("Highlight"),
            Param.flash: .toggle(true),
            Param.sweepLength: .number(80),
            Param.sweepEdge: .number(150),
        ],
    )

    /// Letters riding a wave a quarter-cycle apart, so the line zigzags.
    static let zigzagWave = preset(
        "zigzag-wave", "Zigzag Wave", "Letters ride a wave while they hold", [
            Param.stagger: .number(50),
            Param.fadeIn: .number(400),
            Param.fadeOut: .number(300),
            Param.riseFrom: .number(30),
            Param.easing: .choice("Expo"),
            Param.holdMotion: .choice("Wave"),
            Param.holdAmount: .number(10),
            Param.holdSpeed: .number(1.2),
            Param.holdPhase: .number(90),
        ],
    )

    /// A title settling into place, shaded across each line.
    ///
    /// From the base colour to pink, so the author's own colour stays the
    /// start of the gradient.
    static let gradientTitle = preset(
        "gradient-title", "Gradient Title", "A title settles in, shaded across each line", [
            Param.unit: .choice("Line"),
            Param.staggerMode: .choice("Spread"),
            Param.staggerSpread: .number(50),
            Param.fadeIn: .number(600),
            Param.fadeOut: .number(400),
            Param.scaleFrom: .number(0.8),
            Param.easing: .choice("Expo"),
            Param.colourMode: .choice("Gradient"),
            Param.colour2: .color(EffectColor(r: 255, g: 120, b: 200)),
            Param.gradientAcross: .choice("Line"),
        ],
    )

    /// Letters rising in and sinking back out in the same order.
    ///
    /// Same is first in, first out: every letter holds for the same time, so
    /// the wave that brought the line in passes straight through it and takes
    /// it away again, each letter shrinking back down to where it rose from.
    static let mirrorOut = preset(
        "mirror-out", "Mirror Out", "Letters leave the way they came, first in first out", [
            Param.stagger: .number(45),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(450),
            Param.riseFrom: .number(40),
            Param.scaleFrom: .number(0.6),
            Param.easing: .choice("Back"),
            Param.exit: .choice("Mirror In"),
            Param.exitStagger: .number(45),
            Param.exitOrder: .choice("Same"),
        ],
    )
}
