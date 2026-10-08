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
    static let images = ParticleBurst.images

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
        let settings = ParticleBurst(text: context, scale: max(0, context.number(Param.size)) / image.source)
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
                return settings.particle(
                    id: "\(glyph.sprite.id)/p\(k)", path: image.path,
                    origin: origin, at: at, rng: &stream,
                )
            }
        }
    }

    // ─── One particle ────────────────────────────────────────────────────────

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
}

extension ParticleBurst {
    /// Read from the text effect's own particle parameters.
    init(text context: EffectContext, scale: Double) {
        self.init(
            scale: scale,
            speed: max(0, context.number(TextGlyphParticles.Param.speed)),
            direction: context.number(TextGlyphParticles.Param.direction),
            spread: min(max(context.number(TextGlyphParticles.Param.spread), 0), 360),
            life: max(1, context.number(TextGlyphParticles.Param.life)),
            gravity: context.number(TextGlyphParticles.Param.gravity),
            colour: context.color(TextGlyphParticles.Param.colour),
            additive: context.toggle(TextGlyphParticles.Param.additive),
        )
    }
}
