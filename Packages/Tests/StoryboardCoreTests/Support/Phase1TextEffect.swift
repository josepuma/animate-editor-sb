@testable import StoryboardCore
import Foundation

/// A frozen copy of `TextEffect` and `TextStagger` as they stood at commit
/// be43127d — the end of the Text Animator's first phase.
///
/// Phase two restructures `sprite()` into stages and adds axes; its contract is
/// that nothing phase one could produce moves, save the one named exception
/// (`RiseFallFix`). This is `git show be43127d:` of both files with only the
/// type names changed, `public` dropped, and the descriptor left out: the
/// context is always built from production's descriptor, so the keys and
/// defaults phase one read are the ones a saved node carries. Do NOT "fix" or
/// tidy it: a divergence here is the signal the snapshot tests exist to raise.
struct Phase1TextEffect {
    init() {}

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
        static let unit = "unit"
        static let waveAmount = "waveAmount"
        static let staggerMode = "staggerMode"
        static let staggerSpread = "staggerSpread"
        static let scatterX = "scatterX"
        static let scatterY = "scatterY"
        static let scatterRotation = "scatterRotation"
        static let scatterScale = "scatterScale"
        static let stretchFromX = "stretchFromX"
        static let stretchFromY = "stretchFromY"
        static let pivot = "pivot"
    }

    /// The stream In Scatter draws from, derived from each glyph's own.
    ///
    /// Its own stream rather than the glyph's: Explode and Drift already draw
    /// from that one, and four more draws ahead of them would hand every saved
    /// burst a different set of headings.
    static let scatterTag = 0x5CA7


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

        let units: [Int] = switch context.choice(Param.unit) {
        case "Word": placed.map(\.word)
        case "Line": placed.map(\.line)
        default: Array(placed.indices)
        }
        let ranks = Phase1TextStagger.ranks(
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
        let delays = Phase1TextStagger.delays(
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

/// Who arrives when, for text.
///
/// Pure on purpose: no sprites, no context, only unit indices in and numbers
/// out. The order and the timing are the part of a text effect that grows axes
/// (units, new orders, a spread mode), and keeping them out of the evaluator
/// keeps both small enough to test without drawing anything.
enum Phase1TextStagger {
    /// A position per glyph in the order its **unit** arrives.
    ///
    /// `units[g]` is the dense unit index of glyph `g` — a word, a line, or the
    /// glyph itself — so every glyph of a unit shares one rank. Returned as
    /// numbers rather than a sorted list for the same reason the old order was:
    /// sprites stay in reading order, and that order is their draw order.
    ///
    /// Doubles because Wave produces fractional positions; for the integer
    /// orders `stagger * rank` has exactly the bits `stagger * Double(Int)` had.
    static func ranks(
        units: [Int],
        order: String,
        waveAmount: Double,
        rng: inout EffectRandom,
    ) -> [Double] {
        guard let last = units.max() else { return [] }
        let count = last + 1

        let perUnit: [Double]
        switch order {
        case "End":
            perUnit = (0..<count).map { Double(count - 1 - $0) }
        case "Centre":
            let middle = Double(count - 1) / 2
            perUnit = (0..<count).map { Double(Int(abs(Double($0) - middle).rounded())) }
        case "Edges":
            // The mirror of Centre: both ends first, the middle last.
            perUnit = (0..<count).map { Double(min($0, count - 1 - $0)) }
        case "Wave":
            // A sine riding on the reading order, so arrivals surge and lag
            // instead of marching. Period of six units; shifted so the earliest
            // is still zero — a negative rank would be a delay before the clip.
            let raw = (0..<count).map { Double($0) + waveAmount * sin(Double($0) * .pi / 3) }
            let floor = raw.min() ?? 0
            perUnit = raw.map { $0 - floor }
        case "Random":
            var positions = Array(0..<count)
            // Fisher-Yates over *units*, through the seeded stream, so the
            // preview and the exported file agree. With one glyph per unit this
            // is the draw sequence the glyph-level shuffle always made.
            for index in stride(from: count - 1, to: 0, by: -1) {
                let swap = rng.integer(in: 0...index)
                positions.swapAt(index, swap)
            }
            perUnit = positions.map(Double.init)
        default:
            perUnit = (0..<count).map(Double.init)
        }

        return units.map { perUnit[$0] }
    }

    /// The delay of each glyph, in milliseconds.
    ///
    /// `Per Unit` is a fixed step per rank, with no ceiling — a long text
    /// simply takes longer, as it always did. `Spread` states the stagger as a
    /// share of `window` instead, normalised by the highest rank, so the last
    /// unit lands at exactly `spread`% of the room and the whole line scales
    /// with the clip. `window` is what is left after the entrance and the exit
    /// have taken their time, which is what guarantees nobody arrives after
    /// the exit has begun.
    static func delays(
        ranks: [Double],
        mode: String,
        stagger: Double,
        spread: Double,
        window: Double,
    ) -> [Double] {
        if mode == "Spread" {
            let top = ranks.max() ?? 0
            // One unit has nothing to spread across, and dividing by a zero
            // rank would be NaN.
            guard top > 0 else { return ranks.map { _ in 0 } }
            return ranks.map { $0 / top * spread / 100 * window }
        }
        return ranks.map { stagger * $0 }
    }
}
