import Foundation

/// Particles a glyph throws off at its own moments.
///
/// What a compound cannot do. A layer starts at the clip's local zero and
/// knows nothing about the letters above it, so a burst on a layer fires once
/// for the whole line — while a line staggered across a second lands one
/// letter at a time. Sparks that should hit when *each* letter hits have to
/// come from the glyph, and that is the only thing this adds.
///
/// Three moments, each a different reading of the same burst:
/// - **Land**: all at once, where the glyph comes to rest — impact.
/// - **Trail**: spread along the entrance, where the glyph was at each instant
///   — a comet's tail.
/// - **Disintegrate**: spread over the exit, from anywhere inside the glyph's
///   box — the letter coming apart as it fades.
///
/// Where the glyph *is* comes from the resolver reading the glyph's own
/// finished commands, the same one that draws it. Working the position out
/// again from the entrance numbers would be a second answer to that question,
/// and the two would drift apart the first time the entrance changed.
///
/// Pure like the other text stages, and drawing from its own stream: the
/// glyph's stream feeds Explode and Drift, and a draw ahead of them would hand
/// every saved burst different headings.
enum TextGlyphParticles {
    static let tag = 0x9A27_0001

    /// Per glyph. A burst reads as a burst well before this; past it, the
    /// cost — a sprite and its commands each — buys nothing anyone sees.
    static let maximumPerGlyph = 24

    /// For the whole line. A long line with a big burst would otherwise
    /// write thousands of sprites; the per-glyph count gives way instead.
    static let maximumTotal = 1200

    enum Param {
        static let mode = "particleMode"
        static let count = "particleCount"
        static let sprite = "particleSprite"
        static let size = "particleSize"
        static let speed = "particleSpeed"
        static let direction = "particleDirection"
        static let spread = "particleSpread"
        static let life = "particleLife"
        static let gravity = "particleGravity"
        static let colour = "particleColour"
        static let additive = "particleAdditive"
    }

    enum Mode: String, CaseIterable {
        case none = "None", land = "Land", trail = "Trail", disintegrate = "Disintegrate"
    }

    /// The images on offer, by what they look like, and how wide each is
    /// drawn — `Size` is in pixels, and the same scale draws a 512 texture
    /// eight times the size of a 64 one.
    static let images: [(name: String, path: String, source: Double)] = [
        ("Spark", BuiltInSprite.glow, 64),
        ("Dot", BuiltInSprite.soft, 64),
        ("Dust", BuiltInSprite.smoke, 64),
        ("Star", BuiltInSprite.star, 64),
        ("Square", BuiltInSprite.fill, 64),
        ("Sparkle", BuiltInSprite.sparkle, 512),
        ("Ember", BuiltInSprite.ember, 512),
    ]

    static let parameters: [EffectParameter] = {
        let on = Mode.allCases.filter { $0 != .none }.map(\.rawValue)
        func shown() -> EffectParameter.Condition { .init(parameter: Param.mode, isAnyOf: on) }
        return [
            // Off is the default: a placement gives text, not fireworks.
            EffectParameter(
                id: Param.mode, name: "Particles", group: "Particles",
                defaultValue: .choice(Mode.none.rawValue), options: Mode.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: Param.count, name: "Count", group: "Particles",
                defaultValue: .number(8), range: 1...Double(maximumPerGlyph), step: 1,
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.sprite, name: "Sprite", group: "Particles",
                defaultValue: .choice("Spark"), options: images.map(\.name),
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.size, name: "Size", group: "Particles",
                defaultValue: .number(10), range: 1...120, step: 1, unit: "px",
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.speed, name: "Speed", group: "Particles",
                defaultValue: .number(120), range: 0...1200, step: 5, unit: "px/s",
                shownWhen: shown(),
            ),
            // The emitter's convention: 270 is up, because screen y grows down.
            EffectParameter(
                id: Param.direction, name: "Direction", group: "Particles",
                defaultValue: .number(270), range: 0...360, step: 5, unit: "°",
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.spread, name: "Spread", group: "Particles",
                defaultValue: .number(360), range: 0...360, step: 5, unit: "°",
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.life, name: "Life", group: "Particles",
                defaultValue: .number(700), range: 50...5000, step: 10, unit: "ms",
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.gravity, name: "Gravity", group: "Particles",
                defaultValue: .number(0), range: -2000...2000, step: 10, unit: "px/s²",
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.colour, name: "Colour", group: "Particles",
                defaultValue: .color(EffectColor(r: 255, g: 255, b: 255)),
                shownWhen: shown(),
            ),
            EffectParameter(
                id: Param.additive, name: "Additive", group: "Particles",
                defaultValue: .toggle(true),
                shownWhen: shown(),
            ),
        ]
    }()

    /// One glyph as the particles see it: its finished sprite, its moments,
    /// and the half-extents of its box.
    struct Glyph {
        var index: Int
        var sprite: StoryboardSprite
        var birth: Double
        var landed: Double
        var exitStart: Double
        var life: Double
        var hasExit: Bool
        var halfWidth: Double
        var halfHeight: Double
    }

    static func sprites(
        for glyphs: [Glyph], context: EffectContext, rng: EffectRandom,
    ) -> [StoryboardSprite] {
        let mode = Mode(rawValue: context.choice(Param.mode)) ?? .none
        guard mode != .none, !glyphs.isEmpty else { return [] }

        let perGlyph = min(
            Int(context.number(Param.count).rounded()),
            maximumPerGlyph,
            maximumTotal / glyphs.count,
        )
        guard perGlyph > 0 else { return [] }

        let image = images.first { $0.name == context.choice(Param.sprite) } ?? images[0]
        let settings = Settings(context: context, scale: max(0, context.number(Param.size)) / image.source)
        let root = rng.stream(tag)

        return glyphs.flatMap { glyph -> [StoryboardSprite] in
            guard let prepared = StoryboardResolver.prepare([glyph.sprite]).first else { return [] }
            var stream = root.stream(glyph.index)
            return (0 ..< perGlyph).compactMap { k in
                guard let at = moment(k, of: perGlyph, glyph: glyph, mode: mode, rng: &stream) else { return nil }
                let source = StoryboardResolver.state(of: prepared, at: at)
                var origin = (x: source.x, y: source.y)
                // Coming apart from anywhere in the letter, not from its middle:
                // a dissolve that starts at one point reads as a spark.
                if mode == .disintegrate {
                    origin.x += stream.symmetric(glyph.halfWidth * abs(source.scaleX))
                    origin.y += stream.symmetric(glyph.halfHeight * abs(source.scaleY))
                }
                return particle(
                    id: "\(glyph.sprite.id)/p\(k)", path: image.path,
                    origin: origin, at: at, settings: settings, rng: &stream,
                )
            }
        }
    }

    // ─── One particle ────────────────────────────────────────────────────────

    private struct Settings {
        var scale: Double
        var speed: Double
        var direction: Double
        var spread: Double
        var life: Double
        var gravity: Double
        var colour: EffectColor
        var additive: Bool

        init(context: EffectContext, scale: Double) {
            self.scale = scale
            speed = max(0, context.number(Param.speed))
            direction = context.number(Param.direction)
            spread = min(max(context.number(Param.spread), 0), 360)
            life = max(1, context.number(Param.life))
            gravity = context.number(Param.gravity)
            colour = context.color(Param.colour)
            additive = context.toggle(Param.additive)
        }
    }

    /// When particle `k` of `count` leaves its glyph, or `nil` if the glyph
    /// never has that moment.
    private static func moment(
        _ k: Int, of count: Int, glyph: Glyph, mode: Mode, rng: inout EffectRandom,
    ) -> Double? {
        // Evenly by index along a window, so a trail is a trail and not a
        // clump: a sorted draw bunches, and the eye reads the bunches.
        let along = (Double(k) + 0.5) / Double(count)
        switch mode {
        case .none:
            return nil
        case .land:
            // A few tens of milliseconds of scatter: an impact all on one frame
            // reads as a single sprite popping.
            return glyph.landed + rng.unit() * 30
        case .trail:
            guard glyph.landed > glyph.birth else { return nil }
            return glyph.birth + (glyph.landed - glyph.birth) * along
        case .disintegrate:
            // No exit, nothing to come apart in: the clip's last 400ms stand
            // in, so the letter still dissolves as it disappears.
            let start = glyph.hasExit ? glyph.exitStart : max(glyph.landed, glyph.life - 400)
            guard glyph.life > start else { return nil }
            return start + (glyph.life - start) * along
        }
    }

    private static func particle(
        id: String,
        path: String,
        origin: (x: Double, y: Double),
        at birth: Double,
        settings: Settings,
        rng: inout EffectRandom,
    ) -> StoryboardSprite {
        // A burst of identical particles is a ring, not a burst: speed and
        // life vary so the field has depth.
        let angle = (settings.direction + rng.symmetric(settings.spread / 2)) * .pi / 180
        let speed = settings.speed * (0.5 + rng.unit())
        let life = settings.life * (0.7 + 0.6 * rng.unit())
        let seconds = life / 1000
        let velocity = (x: cos(angle) * speed, y: sin(angle) * speed)

        func position(_ fraction: Double) -> (x: Double, y: Double) {
            let t = seconds * fraction
            return (
                origin.x + velocity.x * t,
                origin.y + velocity.y * t + 0.5 * settings.gravity * t * t,
            )
        }

        var sprite = StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: path,
            defaultX: origin.x, defaultY: origin.y,
        )
        let end = birth + life

        // A straight path is one command; a falling one is a curve, and `_M`
        // only draws lines, so it goes as a few chords.
        let segments = settings.gravity == 0 ? 1 : 4
        for segment in 0 ..< segments {
            let from = position(Double(segment) / Double(segments))
            let to = position(Double(segment + 1) / Double(segments))
            sprite.commands.append(Command(
                easing: .linear,
                startTime: birth + life * Double(segment) / Double(segments),
                endTime: birth + life * Double(segment + 1) / Double(segments),
                payload: .move(startX: from.x, startY: from.y, endX: to.x, endY: to.y),
            ))
        }
        // Holds bright, then goes: a linear fade spends half its life looking
        // half there.
        sprite.commands.append(Command(
            easing: .quadIn, startTime: birth, endTime: end, payload: .fade(start: 1, end: 0),
        ))
        sprite.commands.append(Command(
            easing: .linear, startTime: birth, endTime: end,
            payload: .scale(start: settings.scale, end: settings.scale * 0.3),
        ))
        let colour = settings.colour
        if colour.r != 255 || colour.g != 255 || colour.b != 255 {
            sprite.commands.append(Command(
                easing: .linear, startTime: birth, endTime: birth,
                payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                ),
            ))
        }
        if settings.additive {
            sprite.commands.append(Command(
                easing: .linear, startTime: birth, endTime: end, payload: .parameter(.additive),
            ))
        }
        return sprite
    }
}
