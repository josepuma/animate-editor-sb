import Foundation

/// Text, drawn one sprite per character.
///
/// Per character and not per line, because that is what makes text animate:
/// letters arriving one after another, rising, spinning, scattering. A single
/// sprite holding a whole word can only move as a word — which is a caption,
/// not motion graphics.
///
/// The cost is real and worth naming: a line of forty characters is forty
/// sprites, and each one carries its own commands into the file. Long
/// paragraphs are not what this is for.
public struct TextEffect: Effect {
    public init() {}

    public enum Param {
        public static let text = "text"
        public static let font = "font"
        public static let size = "size"
        public static let bold = "bold"
        public static let italic = "italic"
        public static let tracking = "tracking"
        public static let lineHeight = "lineHeight"
        public static let color = "color"
        public static let additive = "additive"
        public static let stagger = "stagger"
        public static let staggerFrom = "staggerFrom"
        public static let fadeIn = "fadeIn"
        public static let fadeOut = "fadeOut"
        public static let riseFrom = "riseFrom"
        public static let driftFrom = "driftFrom"
        public static let easing = "easing"
        public static let exit = "exit"
        public static let exitForce = "exitForce"
        public static let driftX = "driftX"
        public static let driftY = "driftY"
        public static let scaleFrom = "scaleFrom"
        public static let spinFrom = "spinFrom"
        public static let unit = "unit"
        public static let waveAmount = "waveAmount"
        public static let staggerMode = "staggerMode"
        public static let staggerSpread = "staggerSpread"
        public static let scatterX = "scatterX"
        public static let scatterY = "scatterY"
        public static let scatterRotation = "scatterRotation"
        public static let scatterScale = "scatterScale"
        public static let stretchFromX = "stretchFromX"
        public static let stretchFromY = "stretchFromY"
        public static let pivot = "pivot"
    }

    /// The stream In Scatter draws from, derived from each glyph's own.
    ///
    /// Its own stream rather than the glyph's: Explode and Drift already draw
    /// from that one, and four more draws ahead of them would hand every saved
    /// burst a different set of headings.
    static let scatterTag = 0x5CA7

    public static let descriptor = EffectDescriptor(
        type: "text",
        name: "Text",
        category: .generate,
        systemImage: "textformat",
        parameters: [
            EffectParameter(
                id: Param.text, name: "Text", group: "Content",
                defaultValue: .text("HELLO"),
            ),
            EffectParameter(
                id: Param.font, name: "Font", group: "Content",
                defaultValue: .text("Helvetica"),
            ),
            EffectParameter(
                id: Param.size, name: "Size", group: "Content",
                defaultValue: .number(48), range: 8...400, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.bold, name: "Bold", group: "Content",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.italic, name: "Italic", group: "Content",
                defaultValue: .toggle(false),
            ),

            EffectParameter(
                id: Param.tracking, name: "Tracking", group: "Layout",
                defaultValue: .number(0), range: -40...200, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.lineHeight, name: "Line Height", group: "Layout",
                defaultValue: .number(1.2), range: 0.5...4, step: 0.05,
            ),

            EffectParameter(
                id: Param.color, name: "Colour", group: "Appearance",
                defaultValue: .color(EffectColor(r: 255, g: 255, b: 255)),
            ),
            EffectParameter(
                id: Param.additive, name: "Additive", group: "Appearance",
                defaultValue: .toggle(false),
            ),

            // Every animation parameter rests at nothing.
            //
            // Dropping a text effect gives text, not a performance: a stagger
            // and a fade nobody asked for is animation appearing out of a
            // placement, and it has to be found and switched off before the
            // plain case can be had. The presets are where the moves live —
            // the same rule a placed effect already follows elsewhere.
            //
            // Grouped by the question each answers — in what order, how it
            // arrives, how loose, how it holds and leaves — instead of one
            // "Animation" block thirty rows long. The groups are only labels:
            // moving a parameter between them touches no stored value.

            // ─── Sequence ────────────────────────────────────────────────────
            // What arrives together, and in what order.
            EffectParameter(
                id: Param.unit, name: "Unit", group: "Sequence",
                defaultValue: .choice("Character"),
                options: ["Character", "Word", "Line"],
            ),
            EffectParameter(
                id: Param.staggerFrom, name: "Stagger From", group: "Sequence",
                defaultValue: .choice("Start"),
                options: ["Start", "End", "Centre", "Random", "Edges", "Wave"],
            ),
            EffectParameter(
                id: Param.waveAmount, name: "Wave Amount", group: "Sequence",
                defaultValue: .number(1), range: 0...3, step: 0.1,
                shownWhen: .init(parameter: Param.staggerFrom, isAnyOf: ["Wave"]),
            ),
            EffectParameter(
                id: Param.staggerMode, name: "Stagger Mode", group: "Sequence",
                defaultValue: .choice("Per Unit"),
                options: ["Per Unit", "Spread"],
            ),
            EffectParameter(
                id: Param.stagger, name: "Stagger", group: "Sequence",
                defaultValue: .number(0), range: 0...1000, step: 5, unit: "ms",
                shownWhen: .init(parameter: Param.staggerMode, isAnyOf: ["Per Unit"]),
            ),
            EffectParameter(
                id: Param.staggerSpread, name: "Spread", group: "Sequence",
                defaultValue: .number(60), range: 0...100, step: 1, unit: "%",
                shownWhen: .init(parameter: Param.staggerMode, isAnyOf: ["Spread"]),
            ),

            // ─── Entrance ────────────────────────────────────────────────────
            EffectParameter(
                id: Param.fadeIn, name: "Fade In", group: "Entrance",
                defaultValue: .number(0), range: 0...5000, step: 10, unit: "ms",
            ),
            // The curve is what separates a fall from a drop, a slide from a
            // snap. Fixed at one ease, every preset reads the same however its
            // numbers differ.
            EffectParameter(
                id: Param.easing, name: "Easing", group: "Entrance",
                defaultValue: .choice("Ease Out"),
                options: ["Linear", "Ease Out", "Back", "Elastic", "Bounce", "Expo"],
            ),
            EffectParameter(
                id: Param.riseFrom, name: "Rise From", group: "Entrance",
                defaultValue: .number(0), range: -400...400, step: 1, unit: "px",
            ),
            // Horizontal as well as vertical, so letters can sweep in from a
            // side rather than only from above or below. One axis alone makes
            // every entrance a variation of the same move.
            EffectParameter(
                id: Param.driftFrom, name: "Drift From", group: "Entrance",
                defaultValue: .number(0), range: -800...800, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.scaleFrom, name: "Scale From", group: "Entrance",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            EffectParameter(
                id: Param.spinFrom, name: "Spin From", group: "Entrance",
                defaultValue: .number(0), range: -720...720, step: 5, unit: "°",
            ),
            // One axis squashed is a card turning or a letter unfolding, which
            // a uniform scale cannot say. At 1 they write nothing.
            EffectParameter(
                id: Param.stretchFromX, name: "Stretch From X", group: "Entrance",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            EffectParameter(
                id: Param.stretchFromY, name: "Stretch From Y", group: "Entrance",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            // What a glyph scales and turns about. Bottom is the bottom edge
            // of the glyph's texture box, not the typographic baseline: the
            // box is what a sprite's origin can name, and it holds the same
            // place in every glyph of a style, so a line still sits level.
            EffectParameter(
                id: Param.pivot, name: "Pivot", group: "Entrance",
                defaultValue: .choice("Centre"),
                options: ["Centre", "Bottom"],
            ),

            // ─── Scatter ─────────────────────────────────────────────────────
            // Where each glyph starts from, jittered on its own. Rise and Drift
            // move the whole line the same way; scatter is what makes letters
            // assemble out of a cloud rather than slide in as a block.
            EffectParameter(
                id: Param.scatterX, name: "Scatter X", group: "Scatter",
                defaultValue: .number(0), range: 0...800, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.scatterY, name: "Scatter Y", group: "Scatter",
                defaultValue: .number(0), range: 0...600, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.scatterRotation, name: "Scatter Rotation", group: "Scatter",
                defaultValue: .number(0), range: 0...360, step: 5, unit: "°",
            ),
            EffectParameter(
                id: Param.scatterScale, name: "Scatter Scale", group: "Scatter",
                defaultValue: .number(0), range: 0...3, step: 0.05,
            ),

            // ─── Hold & Exit ─────────────────────────────────────────────────
            // Movement across the whole clip, not just its ends.
            //
            // A line that arrives, sits perfectly still, and leaves is three
            // separate moments. Letting it travel while it is up is what turns
            // those into one shot — the drift a title has as it holds.
            EffectParameter(
                id: Param.driftX, name: "Travel X", group: "Hold & Exit",
                defaultValue: .number(0), range: -800...800, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.driftY, name: "Travel Y", group: "Hold & Exit",
                defaultValue: .number(0), range: -600...600, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.fadeOut, name: "Fade Out", group: "Hold & Exit",
                defaultValue: .number(0), range: 0...5000, step: 10, unit: "ms",
            ),
            // Leaving is its own move: text that arrives with character and
            // then simply dissolves is half an animation.
            EffectParameter(
                id: Param.exit, name: "Exit", group: "Hold & Exit",
                defaultValue: .choice("Fade"),
                options: ["Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift"],
            ),
            // How far Explode and Drift throw. Under any other exit it does
            // nothing, and a control that does nothing lies.
            EffectParameter(
                id: Param.exitForce, name: "Exit Force", group: "Hold & Exit",
                defaultValue: .number(220), range: 0...1200, step: 10, unit: "px",
                shownWhen: .init(parameter: Param.exit, isAnyOf: ["Explode", "Drift"]),
            ),
        ],
    )

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let content = context.text(Param.text)
        guard !content.isEmpty, context.duration > 0 else { return [] }

        let style = TextStyle(
            font: context.text(Param.font),
            size: context.number(Param.size),
            isBold: context.toggle(Param.bold),
            isItalic: context.toggle(Param.italic),
        )

        let placed = layout(content, style: style, context: context)
        guard !placed.isEmpty else { return [] }

        let units: [Int] = switch context.choice(Param.unit) {
        case "Word": placed.map(\.word)
        case "Line": placed.map(\.line)
        default: Array(placed.indices)
        }
        let ranks = TextStagger.ranks(
            units: units,
            order: context.choice(Param.staggerFrom),
            waveAmount: context.number(Param.waveAmount),
            rng: &rng,
        )
        // The room a stagger can use: what is left once the entrance has run
        // and the exit has made room for itself.
        let window = max(
            0,
            context.duration - max(0, context.number(Param.fadeIn)) - max(0, context.number(Param.fadeOut)),
        )
        let delays = TextStagger.delays(
            ranks: ranks,
            mode: context.choice(Param.staggerMode),
            stagger: max(0, context.number(Param.stagger)),
            spread: context.number(Param.staggerSpread),
            window: window,
        )

        return placed.enumerated().map { index, glyph -> StoryboardSprite in
            // A stream per character, so raising the count adds letters rather
            // than reshuffling the ones already placed.
            var stream = rng.stream(index)
            return sprite(
                glyph,
                index: index,
                delay: delays[index],
                style: style,
                context: context,
                rng: &stream,
            )
        }
    }

    // ─── Layout ──────────────────────────────────────────────────────────────

    /// One character with the place it occupies, relative to the clip's centre.
    private struct PlacedGlyph {
        var character: Character
        var x: Double
        var y: Double
        /// Dense indices of the word and the line this glyph belongs to.
        /// Dense, because End, Centre and Spread read the highest one — a
        /// blank line or a run of spaces must not leave gaps in the count.
        var word: Int
        var line: Int
        /// The glyph's own metrics, which size its texture box.
        var size: TextMetrics.Glyph
    }

    /// Lays the text out around its own centre.
    ///
    /// Around the centre rather than from a corner, because the clip's
    /// transform turns and scales about that point — text laid out from a
    /// corner would swing around one end when rotated.
    private func layout(
        _ content: String,
        style: TextStyle,
        context: EffectContext,
    ) -> [PlacedGlyph] {
        let tracking = context.number(Param.tracking)
        let lineHeight = style.size * context.number(Param.lineHeight)

        let lines = content.components(separatedBy: "\n")
        var placed: [PlacedGlyph] = []

        // Measured first so each line can be justified against its own width.
        let widths = lines.map { line in
            line.reduce(0.0) { $0 + TextMetrics.glyph($1, style: style).width + tracking }
                - (line.isEmpty ? 0 : tracking)
        }

        var word = -1
        var lineIndex = -1
        let blockHeight = lineHeight * Double(lines.count)
        let originY = -blockHeight / 2 + lineHeight / 2

        for (row, line) in lines.enumerated() {
            // Centred on the clip, which is also what the transform turns
            // about. There is no alignment control: it would need more than one
            // line to mean anything, and the field holds one.
            var cursor = -widths[row] / 2
            var inWord = false
            var lineStarted = false

            for character in line {
                let glyph = TextMetrics.glyph(character, style: style)
                // Spaces take their width and draw nothing.
                if character.isWhitespace {
                    inWord = false
                } else {
                    // Punctuation is not whitespace, so it stays with its word.
                    if !inWord { word += 1; inWord = true }
                    if !lineStarted { lineIndex += 1; lineStarted = true }
                    // Centred on the advance, which is what the texture spans:
                    // the glyph's own drawing sits inside that box wherever the
                    // font puts it, and moving the sprite to the ink's centre
                    // instead would undo the spacing the font describes.
                    placed.append(PlacedGlyph(
                        character: character,
                        x: cursor + glyph.width / 2,
                        y: originY + lineHeight * Double(row),
                        word: word,
                        line: lineIndex,
                        size: glyph,
                    ))
                }
                cursor += glyph.width + tracking
            }
        }

        return placed
    }

    /// The curve an entrance travels on.
    ///
    /// Named rather than exposed as the full easing list: these are the six
    /// that read as distinct movements, and a picker of thirty-five curves is a
    /// reference table rather than a choice.
    private static func easing(named name: String) -> Easing {
        switch name {
        case "Linear": .linear
        case "Back": .backOut
        case "Elastic": .elasticOut
        case "Bounce": .bounceOut
        case "Expo": .expoOut
        default: .out
        }
    }

    // ─── One character ───────────────────────────────────────────────────────

    private func sprite(
        _ glyph: PlacedGlyph,
        index: Int,
        delay: Double,
        style: TextStyle,
        context: EffectContext,
        rng: inout EffectRandom,
    ) -> StoryboardSprite {
        let birth = delay
        let death = context.duration
        let fadeIn = max(0, context.number(Param.fadeIn))
        let fadeOut = max(0, context.number(Param.fadeOut))

        // When *this* character leaves — never before it has finished
        // arriving.
        //
        // `birth` carries the stagger and so differs per character, while
        // `death` is the clip's end and is the same for all of them. Taken as
        // `death - fadeOut` alone, every character's fade-out fired at the
        // same moment while the late ones were still fading in — two commands
        // fighting over opacity, which osu! settles by letting the last one
        // written win. Measured on `cascade` over sixteen characters in a
        // two-second clip: fade-outs at 1500 against fade-ins running to 2350.
        //
        // A character that cannot both arrive and leave inside the clip keeps
        // its arrival and loses the exit: appearing and then vanishing is
        // still the line being read, while a fade-out over an unfinished
        // fade-in is a glyph that flickers and never lands.
        //
        // One place, because the fade, the travel and the exit all need the
        // same answer — three copies of it is how one of them ends up a few
        // hundred milliseconds off.
        let exitStart = max(birth + fadeIn, death - fadeOut)

        // Bottom moves the anchor down by half the box and the position with
        // it, so a glyph at rest is drawn exactly where Centre draws it: only
        // what it scales and turns about changes. Every move below is relative
        // to `defaultY`, so rises and falls travel the same distance.
        let onBottom = context.choice(Param.pivot) == "Bottom"
        let centreY = TransformProperty.y.defaultValue + glyph.y
        var sprite = StoryboardSprite(
            id: "\(context.idPrefix)/c\(index)",
            layer: .foreground,
            origin: onBottom ? .bottomCentre : .centre,
            filePath: TextSprite.path(for: glyph.character, style: style),
            defaultX: TransformProperty.x.defaultValue + glyph.x,
            defaultY: onBottom ? centreY + TextSprite.boxHeight(glyph.size, style: style) / 2 : centreY,
        )

        // Opacity first, and always present: without a fade the sprite holds
        // its default from the start of the file, so every character would be
        // visible before its own stagger reached it.
        if fadeIn > 0 {
            sprite.commands.append(Command(
                easing: .out, startTime: birth, endTime: birth + fadeIn,
                payload: .fade(start: 0, end: 1),
            ))
            // Held to the end, or the sprite is only alive for its own fade —
            // a character that appears and then stops existing.
            // Held from arrival to whenever this character leaves. Without
            // the hold a sprite lives only for its own fade — a character
            // that appears and then stops existing — and a character whose
            // exit was dropped for want of room needs it to reach `death`.
            if exitStart >= death || fadeOut == 0 {
                sprite.commands.append(Command(
                    easing: .linear, startTime: birth + fadeIn, endTime: death,
                    payload: .fade(start: 1, end: 1),
                ))
            }
        } else {
            // No fade still means visible: without a command the sprite holds
            // its default opacity from the beginning of the file, so every
            // character would be on screen before its own stagger reached it.
            sprite.commands.append(Command(
                easing: .linear, startTime: birth, endTime: fadeOut > 0 ? birth : death,
                payload: .fade(start: 1, end: 1),
            ))
        }
        // Only when there is room for it after the character has arrived.
        if fadeOut > 0, exitStart < death {
            sprite.commands.append(Command(
                easing: .linear, startTime: exitStart, endTime: death,
                payload: .fade(start: 1, end: 0),
            ))
        }

        // The entrance: each character travels from wherever it was told to
        // start to where the layout puts it.
        let curve = Self.easing(named: context.choice(Param.easing))
        let rise = context.number(Param.riseFrom)
        let drift = context.number(Param.driftFrom)
        let scatter = Scatter(context: context, stream: rng.stream(Self.scatterTag))

        // Both axes in one command when both move: `_M` carries the pair, and
        // two separate commands would each fight for the same position.
        if fadeIn > 0, rise != 0 || drift != 0 || scatter.x != nil || scatter.y != nil {
            sprite.commands.append(Command(
                easing: curve, startTime: birth, endTime: birth + fadeIn,
                payload: .move(
                    startX: Scatter.adding(scatter.x, to: sprite.defaultX + drift),
                    startY: Scatter.adding(scatter.y, to: sprite.defaultY + rise),
                    endX: sprite.defaultX,
                    endY: sprite.defaultY,
                ),
            ))
        }

        let scaleFrom = context.number(Param.scaleFrom)
        let stretchX = context.number(Param.stretchFromX)
        let stretchY = context.number(Param.stretchFromY)
        // A stretched sprite speaks `_V` for its whole life, exit included.
        //
        // osu! keeps `S` and `V` as two properties that multiply, while the
        // editor's resolver lets a `V` track override `S` outright: a sprite
        // holding both draws one way here and another in the game. One
        // vocabulary per sprite is what keeps the preview and the file in
        // agreement, and plain `_S` stays where nothing is stretched — one
        // number where a vector would cost two.
        let usesVector = fadeIn > 0 && (stretchX != 1 || stretchY != 1)
        if scaleFrom != 1 || scatter.scale != nil || usesVector, fadeIn > 0 {
            // Clamped only when jittered: a glyph cannot start inside out, and
            // an unjittered start has to stay the very number it always was.
            let start = scatter.scale.map { max(0, scaleFrom + $0) } ?? scaleFrom
            sprite.commands.append(Command(
                easing: curve, startTime: birth, endTime: birth + fadeIn,
                payload: usesVector
                    ? .vectorScale(startX: start * stretchX, startY: start * stretchY, endX: 1, endY: 1)
                    : .scale(start: start, end: 1),
            ))
        }

        let spin = context.number(Param.spinFrom)
        if spin != 0 || scatter.rotation != nil, fadeIn > 0 {
            sprite.commands.append(Command(
                easing: curve, startTime: birth, endTime: birth + fadeIn,
                payload: .rotate(start: Scatter.adding(scatter.rotation, to: spin) * .pi / 180, end: 0),
            ))
        }

        // The travel, over the span the character is actually up: after its own
        // entrance has landed and before the exit takes over. Sharing those
        // spans would have two commands writing the same position, and the
        // later one simply wins.
        let travelX = context.number(Param.driftX)
        let travelY = context.number(Param.driftY)
        let travelStart = birth + fadeIn
        if travelX != 0 || travelY != 0, exitStart > travelStart {
            sprite.commands.append(Command(
                easing: .linear, startTime: travelStart, endTime: exitStart,
                payload: .move(
                    startX: sprite.defaultX,
                    startY: sprite.defaultY,
                    endX: sprite.defaultX + travelX,
                    endY: sprite.defaultY + travelY,
                ),
            ))
        }

        // The exit, which mirrors whichever entrance was chosen — text that
        // arrives with character and then merely dissolves is half a move.
        if fadeOut > 0, exitStart < death {
            let start = exitStart
            switch context.choice(Param.exit) {
            case "Rise":
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: start, endTime: death,
                    payload: .moveY(start: sprite.defaultY, end: sprite.defaultY - 60),
                ))
            case "Fall":
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: start, endTime: death,
                    payload: .moveY(start: sprite.defaultY, end: sprite.defaultY + 60),
                ))
            case "Shrink":
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: start, endTime: death,
                    payload: usesVector
                        ? .vectorScale(startX: 1, startY: 1, endX: 0.2, endY: 0.2)
                        : .scale(start: 1, end: 0.2),
                ))
            case "Grow":
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: start, endTime: death,
                    payload: usesVector
                        ? .vectorScale(startX: 1, startY: 1, endX: 2, endY: 2)
                        : .scale(start: 1, end: 2),
                ))
            case "Spin":
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: start, endTime: death,
                    payload: .rotate(start: 0, end: .pi),
                ))
            case "Explode", "Drift":
                // Each character leaves on its own heading.
                //
                // A shared direction is a slide, however fast: what reads as an
                // explosion is that no two letters agree on where they are
                // going. Explode throws them outward from the line's centre —
                // which is what a burst does — while Drift picks a heading at
                // random, for smoke rather than shrapnel.
                let force = context.number(Param.exitForce)
                let angle: Double = if context.choice(Param.exit) == "Explode" {
                    // Outward from the centre, nudged so a character sitting on
                    // the centre line still has somewhere to go.
                    atan2(glyph.y, glyph.x == 0 ? 0.001 : glyph.x) + rng.symmetric(0.4)
                } else {
                    rng.between(0, .pi * 2)
                }

                let distance = force * rng.between(0.6, 1.4)
                // From wherever the travel left it, or the character snaps back
                // to its starting place before flying off.
                let fromX = sprite.defaultX + travelX
                let fromY = sprite.defaultY + travelY
                sprite.commands.append(Command(
                    easing: .quadOut, startTime: start, endTime: death,
                    payload: .move(
                        startX: fromX,
                        startY: fromY,
                        endX: fromX + cos(angle) * distance,
                        endY: fromY + sin(angle) * distance,
                    ),
                ))
                // Tumbling as it goes, each its own way — debris does not spin
                // in unison.
                sprite.commands.append(Command(
                    easing: .linear, startTime: start, endTime: death,
                    payload: .rotate(start: 0, end: rng.symmetric(.pi * 1.5)),
                ))
            default:
                break
            }
        }

        // Tinted rather than drawn in colour: the glyph texture is white, so
        // one image serves every colour it is used in.
        let colour = context.color(Param.color)
        if colour != EffectColor(r: 255, g: 255, b: 255) {
            sprite.commands.append(Command(
                easing: .linear, startTime: birth, endTime: birth,
                payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                ),
            ))
        }

        if context.toggle(Param.additive) {
            sprite.commands.append(Command(
                easing: .linear, startTime: birth, endTime: death,
                payload: .parameter(.additive),
            ))
        }

        return sprite
    }

    // ─── In Scatter ──────────────────────────────────────────────────────────

    /// One glyph's entrance jitter: `nil` on every axis whose amplitude is 0.
    ///
    /// All four are drawn whenever any is, in a fixed order, so turning one axis
    /// on never moves another's numbers. An axis at 0 contributes nothing at
    /// all rather than a drawn zero: `x + -0.0` is `x`, but the rule "an
    /// untouched axis is not in the arithmetic" is easier to keep than to
    /// reason about every time.
    private struct Scatter {
        var x: Double?
        var y: Double?
        var rotation: Double?
        var scale: Double?

        init(context: EffectContext, stream: EffectRandom) {
            let amplitudes = [
                context.number(Param.scatterX), context.number(Param.scatterY),
                context.number(Param.scatterRotation), context.number(Param.scatterScale),
            ]
            guard amplitudes.contains(where: { $0 != 0 }) else { return }
            var stream = stream
            let drawn = amplitudes.map { stream.symmetric($0) }
            func kept(_ index: Int) -> Double? { amplitudes[index] != 0 ? drawn[index] : nil }
            x = kept(0)
            y = kept(1)
            rotation = kept(2)
            scale = kept(3)
        }

        static func adding(_ jitter: Double?, to value: Double) -> Double {
            jitter.map { value + $0 } ?? value
        }
    }
}
