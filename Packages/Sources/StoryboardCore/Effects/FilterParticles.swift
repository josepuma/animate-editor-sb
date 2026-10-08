import Foundation

/// The particle controls Disintegrate and Spark Trail share, and how a burst
/// is read from them — declared once, so the two filters cannot drift apart
/// on what "Size" or "Life" means.
enum FilterParticles {
    /// Per sprite. A burst reads as one long before this.
    static let maximumPerSprite = 24

    /// For the whole clip: an emitter of two thousand particles each throwing
    /// twenty-four would write forty-eight thousand sprites. The per-sprite
    /// count gives way instead.
    static let maximumTotal = 1200

    enum Param {
        static let count = "particleCount"
        static let sprite = "particleSprite"
        static let size = "particleSize"
        static let speed = "particleSpeed"
        static let spread = "particleSpread"
        static let life = "particleLife"
        static let gravity = "particleGravity"
        static let colour = "particleColour"
        static let additive = "particleAdditive"
    }

    static func parameters(group: String, count: Double, speed: Double, spread: Double, sprite: String) -> [EffectParameter] {
        [
            EffectParameter(id: Param.count, name: "Count", group: group, defaultValue: .number(count), range: 1...Double(maximumPerSprite), step: 1),
            EffectParameter(id: Param.sprite, name: "Sprite", group: group, defaultValue: .choice(sprite), options: ParticleBurst.images.map(\.name)),
            EffectParameter(id: Param.size, name: "Size", group: group, defaultValue: .number(8), range: 1...120, step: 1, unit: "px"),
            EffectParameter(id: Param.speed, name: "Speed", group: group, defaultValue: .number(speed), range: 0...1200, step: 5, unit: "px/s"),
            EffectParameter(id: Param.spread, name: "Spread", group: group, defaultValue: .number(spread), range: 0...360, step: 5, unit: "°"),
            EffectParameter(id: Param.life, name: "Life", group: group, defaultValue: .number(600), range: 50...5000, step: 10, unit: "ms"),
            EffectParameter(id: Param.gravity, name: "Gravity", group: group, defaultValue: .number(0), range: -2000...2000, step: 10, unit: "px/s²"),
            EffectParameter(id: Param.colour, name: "Colour", group: group, defaultValue: .color(EffectColor(r: 255, g: 255, b: 255))),
            EffectParameter(id: Param.additive, name: "Additive", group: group, defaultValue: .toggle(true)),
        ]
    }

    /// How many each sprite throws: the count, unless the clip total would
    /// pass the cap.
    static func perSprite(_ context: FilterContext, sprites: Int) -> Int {
        guard sprites > 0 else { return 0 }
        return min(Int(context.number(Param.count).rounded()), maximumPerSprite, maximumTotal / sprites)
    }

    static func image(_ context: FilterContext) -> (name: String, path: String, source: Double) {
        ParticleBurst.images.first { $0.name == context.choice(Param.sprite) } ?? ParticleBurst.images[0]
    }

    static func burst(_ context: FilterContext, direction: Double) -> ParticleBurst {
        ParticleBurst(
            scale: max(0, context.number(Param.size)) / image(context).source,
            speed: max(0, context.number(Param.speed)),
            direction: direction,
            spread: min(max(context.number(Param.spread), 0), 360),
            life: max(1, context.number(Param.life)),
            gravity: context.number(Param.gravity),
            colour: context.color(Param.colour),
            additive: context.toggle(Param.additive),
        )
    }

    /// One stream per filter, seeded from its id with FNV — not `hashValue`,
    /// which Swift randomises per process.
    static func stream(_ context: FilterContext) -> EffectRandom {
        EffectRandom(seed: NoiseField.seed(context.idPrefix))
    }
}
