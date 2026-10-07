@testable import StoryboardCore
import Foundation

/// A frozen copy of `TextEffect` as it behaved before the Text Animator work.
///
/// The contract of that change is "nothing that already exists moves": a
/// snapshot fixture would need a record mode and thousands of lines, and an
/// oracle compares any text × seed on demand. It is a byte-for-byte copy of
/// `evaluate`, `layout`, `staggerOrder` and `sprite` — parameter keys are
/// literals on purpose, so it keeps working while production renames or adds
/// to its own `Param` set. Do NOT "fix" or tidy it: a divergence here is the
/// signal the snapshot tests exist to raise.
struct LegacyTextEffect {
    enum Param {
        static let text = "text"
        static let font = "font"
        static let size = "size"
        static let bold = "bold"
        static let italic = "italic"
        static let tracking = "tracking"
        static let lineHeight = "lineHeight"
        static let color = "color"
        static let additive = "additive"
        static let stagger = "stagger"
        static let staggerFrom = "staggerFrom"
        static let fadeIn = "fadeIn"
        static let fadeOut = "fadeOut"
        static let riseFrom = "riseFrom"
        static let driftFrom = "driftFrom"
        static let easing = "easing"
        static let exit = "exit"
        static let exitForce = "exitForce"
        static let driftX = "driftX"
        static let driftY = "driftY"
        static let scaleFrom = "scaleFrom"
        static let spinFrom = "spinFrom"
    }

    func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
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
