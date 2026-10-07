import Foundation

public extension TextEffect {
    /// The presets the Text Animator axes make possible.
    ///
    /// Each one is a move nothing before could name: words or lines arriving
    /// as a block, letters assembling out of a cloud, a stretch that unfolds,
    /// a wave that is not a sweep. Every one is only numbers on the one text
    /// effect — no case in the evaluator knows a preset by name — and none
    /// touches content (text, size, font, colour), so swapping presets never
    /// takes the author's words away.
    static let animatorPresets: [EffectPreset] = [
        wordPop, lineSlide, assemble, slam, stretchIn,
        spiralIn, splitReveal, cascadeWave, titleDrop, unfoldUp,
    ]

    /// Whole words popping in one after another — the lyric-video move.
    static let wordPop = preset(
        "word-pop", "Word Pop", "Words pop in one at a time", [
            Param.unit: .choice("Word"),
            Param.stagger: .number(180),
            Param.fadeIn: .number(300),
            Param.fadeOut: .number(250),
            Param.scaleFrom: .number(0.3),
            Param.easing: .choice("Back"),
            Param.exit: .choice("Shrink"),
        ],
    )

    /// Each line sliding in from the left as a block.
    static let lineSlide = preset(
        "line-slide", "Line Slide", "Lines slide in one after another", [
            Param.unit: .choice("Line"),
            Param.stagger: .number(250),
            Param.fadeIn: .number(500),
            Param.fadeOut: .number(350),
            Param.driftFrom: .number(-220),
            Param.easing: .choice("Expo"),
        ],
    )

    /// Letters flying in from a cloud and locking into the line.
    ///
    /// Spread rather than a stagger in milliseconds: the assembly takes the
    /// same share of the clip however long the line is.
    static let assemble = preset(
        "assemble", "Assemble", "Letters fly in from a cloud and lock into place", [
            Param.staggerFrom: .choice("Random"),
            Param.staggerMode: .choice("Spread"),
            Param.staggerSpread: .number(70),
            Param.fadeIn: .number(700),
            Param.fadeOut: .number(300),
            Param.scatterX: .number(260),
            Param.scatterY: .number(180),
            Param.scatterRotation: .number(180),
            Param.scatterScale: .number(0.6),
            Param.easing: .choice("Expo"),
        ],
    )

    /// Words hitting the screen big and squashed, then blowing out.
    ///
    /// The squash makes it `_V`, and so its Grow exit is `_V` too: a sprite
    /// never mixes the two scale commands.
    static let slam = preset(
        "slam", "Slam", "Words slam down, squashed, one at a time", [
            Param.unit: .choice("Word"),
            Param.stagger: .number(220),
            Param.fadeIn: .number(200),
            Param.fadeOut: .number(300),
            Param.scaleFrom: .number(2.6),
            Param.stretchFromY: .number(0.5),
            Param.easing: .choice("Expo"),
            Param.exit: .choice("Grow"),
        ],
    )

    /// Wide and flat, snapping back to shape.
    static let stretchIn = preset(
        "stretch-in", "Stretch In", "Letters arrive stretched wide and snap to shape", [
            Param.stagger: .number(40),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(300),
            Param.stretchFromX: .number(3),
            Param.stretchFromY: .number(0.2),
            Param.easing: .choice("Expo"),
            Param.exit: .choice("Shrink"),
        ],
    )

    /// Spinning in from nothing, from both ends of the line inward.
    static let spiralIn = preset(
        "spiral-in", "Spiral In", "Letters spin in from both ends", [
            Param.staggerFrom: .choice("Edges"),
            Param.stagger: .number(50),
            Param.fadeIn: .number(600),
            Param.fadeOut: .number(300),
            Param.scaleFrom: .number(0.2),
            Param.spinFrom: .number(360),
            Param.scatterRotation: .number(90),
            Param.easing: .choice("Expo"),
        ],
    )

    /// Opening sideways out of a sliver, from the ends toward the middle.
    static let splitReveal = preset(
        "split-reveal", "Split Reveal", "Letters open sideways from the ends inward", [
            Param.staggerFrom: .choice("Edges"),
            Param.stagger: .number(70),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(300),
            Param.stretchFromX: .number(0.05),
            Param.easing: .choice("Back"),
        ],
    )

    /// A rolling wave rather than a left-to-right sweep.
    static let cascadeWave = preset(
        "cascade-wave", "Cascade Wave", "Letters rise in a rolling wave", duration: 5000, [
            Param.staggerFrom: .choice("Wave"),
            Param.waveAmount: .number(1.5),
            Param.stagger: .number(70),
            Param.fadeIn: .number(700),
            Param.fadeOut: .number(400),
            Param.riseFrom: .number(60),
            Param.easing: .choice("Ease Out"),
        ],
    )

    /// Lines dropping in and landing on their feet.
    ///
    /// Pivot Bottom so the bounce settles onto the line rather than out of
    /// its middle: the letters land, they do not inflate.
    static let titleDrop = preset(
        "title-drop", "Title Drop", "Lines drop in and land on their feet", [
            Param.unit: .choice("Line"),
            Param.staggerMode: .choice("Spread"),
            Param.staggerSpread: .number(60),
            Param.fadeIn: .number(600),
            Param.fadeOut: .number(400),
            Param.riseFrom: .number(-160),
            Param.scaleFrom: .number(1.4),
            Param.easing: .choice("Bounce"),
            Param.pivot: .choice("Bottom"),
            Param.exit: .choice("Fall"),
        ],
    )

    /// Unfolding upward out of the line, like a card standing up.
    ///
    /// `unfold` squashes about the centre; this one grows from the bottom
    /// edge of each glyph's box, so the letters rise out of the line.
    static let unfoldUp = preset(
        "unfold-up", "Unfold Up", "Letters unfold upward from the line", [
            Param.stagger: .number(55),
            Param.fadeIn: .number(450),
            Param.fadeOut: .number(300),
            Param.stretchFromY: .number(0.05),
            Param.pivot: .choice("Bottom"),
            Param.easing: .choice("Back"),
        ],
    )
}
