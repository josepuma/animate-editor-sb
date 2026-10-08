import Foundation

/// One particle thrown off a sprite: a straight or falling path, a fade that
/// holds bright then goes, and a shrink — the burst the text effect's glyph
/// particles and the Destroy filters share.
///
/// One copy, because two particle builders drift: the day one learns to fall
/// in chords and the other does not, the same burst looks different on a
/// letter and on a clip. Its random draws are in a fixed order — moving one
/// would hand every saved burst different headings.
struct ParticleBurst {
    var scale: Double
    var speed: Double
    var direction: Double
    var spread: Double
    var life: Double
    var gravity: Double
    var colour: EffectColor
    var additive: Bool

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

    func particle(
        id: String,
        path: String,
        origin: (x: Double, y: Double),
        at birth: Double,
        rng: inout EffectRandom,
    ) -> StoryboardSprite {
        let settings = self
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
