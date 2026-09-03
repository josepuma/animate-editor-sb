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
    }

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

            // ─── Animation ───────────────────────────────────────────────────
            // Every animation parameter rests at nothing.
            //
            // Dropping a text effect gives text, not a performance: a stagger
            // and a fade nobody asked for is animation appearing out of a
            // placement, and it has to be found and switched off before the
            // plain case can be had. The presets are where the moves live —
            // the same rule a placed effect already follows elsewhere.
            EffectParameter(
                id: Param.stagger, name: "Stagger", group: "Animation",
                defaultValue: .number(0), range: 0...1000, step: 5, unit: "ms",
            ),
            EffectParameter(
                id: Param.staggerFrom, name: "Stagger From", group: "Animation",
                defaultValue: .choice("Start"),
                options: ["Start", "End", "Centre", "Random"],
            ),
            EffectParameter(
                id: Param.fadeIn, name: "Fade In", group: "Animation",
                defaultValue: .number(0), range: 0...5000, step: 10, unit: "ms",
            ),
            EffectParameter(
                id: Param.fadeOut, name: "Fade Out", group: "Animation",
                defaultValue: .number(0), range: 0...5000, step: 10, unit: "ms",
            ),
            EffectParameter(
                id: Param.riseFrom, name: "Rise From", group: "Animation",
                defaultValue: .number(0), range: -400...400, step: 1, unit: "px",
            ),
            // Horizontal as well as vertical, so letters can sweep in from a
            // side rather than only from above or below. One axis alone makes
            // every entrance a variation of the same move.
            EffectParameter(
                id: Param.driftFrom, name: "Drift From", group: "Animation",
                defaultValue: .number(0), range: -800...800, step: 1, unit: "px",
            ),
            // The curve is what separates a fall from a drop, a slide from a
            // snap. Fixed at one ease, every preset reads the same however its
            // numbers differ.
            EffectParameter(
                id: Param.easing, name: "Easing", group: "Animation",
                defaultValue: .choice("Ease Out"),
                options: ["Linear", "Ease Out", "Back", "Elastic", "Bounce", "Expo"],
            ),
            // Leaving is its own move: text that arrives with character and
            // then simply dissolves is half an animation.
            // Movement across the whole clip, not just its ends.
            //
            // A line that arrives, sits perfectly still, and leaves is three
            // separate moments. Letting it travel while it is up is what turns
            // those into one shot — the drift a title has as it holds.
            EffectParameter(
                id: Param.driftX, name: "Travel X", group: "Animation",
                defaultValue: .number(0), range: -800...800, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.driftY, name: "Travel Y", group: "Animation",
                defaultValue: .number(0), range: -600...600, step: 5, unit: "px",
            ),
            EffectParameter(
                id: Param.exitForce, name: "Exit Force", group: "Animation",
                defaultValue: .number(220), range: 0...1200, step: 10, unit: "px",
            ),
            EffectParameter(
                id: Param.exit, name: "Exit", group: "Animation",
                defaultValue: .choice("Fade"),
                options: ["Fade", "Rise", "Fall", "Shrink", "Grow", "Spin", "Explode", "Drift"],
            ),
            EffectParameter(
                id: Param.scaleFrom, name: "Scale From", group: "Animation",
                defaultValue: .number(1), range: 0...5, step: 0.05,
            ),
            EffectParameter(
                id: Param.spinFrom, name: "Spin From", group: "Animation",
                defaultValue: .number(0), range: -720...720, step: 5, unit: "°",
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

        let order = staggerOrder(count: placed.count, mode: context.choice(Param.staggerFrom), rng: &rng)
        let stagger = max(0, context.number(Param.stagger))

        return placed.enumerated().map { index, glyph -> StoryboardSprite in
            // A stream per character, so raising the count adds letters rather
            // than reshuffling the ones already placed.
            var stream = rng.stream(index)
            return sprite(
                glyph,
                index: index,
                delay: stagger * Double(order[index]),
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

        let blockHeight = lineHeight * Double(lines.count)
        let originY = -blockHeight / 2 + lineHeight / 2

        for (row, line) in lines.enumerated() {
            // Centred on the clip, which is also what the transform turns
            // about. There is no alignment control: it would need more than one
            // line to mean anything, and the field holds one.
            var cursor = -widths[row] / 2

            for character in line {
                let glyph = TextMetrics.glyph(character, style: style)
                // Spaces take their width and draw nothing.
                if !character.isWhitespace {
                    // Centred on the advance, which is what the texture spans:
                    // the glyph's own drawing sits inside that box wherever the
                    // font puts it, and moving the sprite to the ink's centre
                    // instead would undo the spacing the font describes.
                    placed.append(PlacedGlyph(
                        character: character,
                        x: cursor + glyph.width / 2,
                        y: originY + lineHeight * Double(row),
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

    // ─── Stagger ─────────────────────────────────────────────────────────────

    /// The order characters arrive in.
    ///
    /// Returned as a position per character rather than a sorted list, so the
    /// sprites stay in reading order — their order in the array is their draw
    /// order, and shuffling that would reorder overlapping glyphs.
    private func staggerOrder(
        count: Int,
        mode: String,
        rng: inout EffectRandom,
    ) -> [Int] {
        switch mode {
        case "End":
            return (0..<count).map { count - 1 - $0 }
        case "Centre":
            let middle = Double(count - 1) / 2
            return (0..<count).map { Int(abs(Double($0) - middle).rounded()) }
        case "Random":
            var positions = Array(0..<count)
            // Fisher-Yates through the seeded stream, so a text effect is as
            // reproducible as an emitter: the preview and the exported file
            // have to agree.
            for index in stride(from: count - 1, to: 0, by: -1) {
                let swap = rng.integer(in: 0...index)
                positions.swapAt(index, swap)
            }
            return positions
        default:
            return Array(0..<count)
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

        var sprite = StoryboardSprite(
            id: "\(context.idPrefix)/c\(index)",
            layer: .foreground,
            origin: .centre,
            filePath: TextSprite.path(for: glyph.character, style: style),
            defaultX: TransformProperty.x.defaultValue + glyph.x,
            defaultY: TransformProperty.y.defaultValue + glyph.y,
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
            if fadeOut == 0 {
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
        if fadeOut > 0 {
            sprite.commands.append(Command(
                easing: .linear, startTime: max(birth, death - fadeOut), endTime: death,
                payload: .fade(start: 1, end: 0),
            ))
        }

        // The entrance: each character travels from wherever it was told to
        // start to where the layout puts it.
        let curve = Self.easing(named: context.choice(Param.easing))
        let rise = context.number(Param.riseFrom)
        let drift = context.number(Param.driftFrom)

        // Both axes in one command when both move: `_M` carries the pair, and
        // two separate commands would each fight for the same position.
        if fadeIn > 0, rise != 0 || drift != 0 {
            sprite.commands.append(Command(
                easing: curve, startTime: birth, endTime: birth + fadeIn,
                payload: .move(
                    startX: sprite.defaultX + drift,
                    startY: sprite.defaultY + rise,
                    endX: sprite.defaultX,
                    endY: sprite.defaultY,
                ),
            ))
        }

        let scaleFrom = context.number(Param.scaleFrom)
        if scaleFrom != 1, fadeIn > 0 {
            sprite.commands.append(Command(
                easing: curve, startTime: birth, endTime: birth + fadeIn,
                payload: .scale(start: scaleFrom, end: 1),
            ))
        }

        let spin = context.number(Param.spinFrom)
        if spin != 0, fadeIn > 0 {
            sprite.commands.append(Command(
                easing: curve, startTime: birth, endTime: birth + fadeIn,
                payload: .rotate(start: spin * .pi / 180, end: 0),
            ))
        }

        // The travel, over the span the character is actually up: after its own
        // entrance has landed and before the exit takes over. Sharing those
        // spans would have two commands writing the same position, and the
        // later one simply wins.
        let travelX = context.number(Param.driftX)
        let travelY = context.number(Param.driftY)
        let exitStart = fadeOut > 0 ? max(birth, death - fadeOut) : death
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
        if fadeOut > 0 {
            let start = max(birth, death - fadeOut)
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
                    payload: .scale(start: 1, end: 0.2),
                ))
            case "Grow":
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: start, endTime: death,
                    payload: .scale(start: 1, end: 2),
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
}
