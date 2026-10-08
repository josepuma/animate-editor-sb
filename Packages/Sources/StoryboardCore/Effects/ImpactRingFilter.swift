import Foundation

/// A shockwave where each move lands: a ring opening and fading at the end
/// position, at the end time.
///
/// Only moves fast enough to land with weight earn one — `Min Speed` — so a
/// slow drift does not ring at every keyframe. Read per command, so a sprite
/// that hops three times rings three times.
public struct ImpactRingFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let size = "size"
        public static let thickness = "thickness"
        public static let duration = "duration"
        public static let minSpeed = "minSpeed"
        public static let colour = "colour"
        public static let additive = "additive"
    }

    /// Rings per sprite, and for the clip: an emitter whose every chord
    /// counted as a landing would ring thousands of times.
    static let maximumPerSprite = 8
    static let maximumTotal = 400

    public static let descriptor = FilterDescriptor(
        type: "impact-ring",
        name: "Impact Ring",
        category: .destroy,
        systemImage: "dot.radiowaves.left.and.right",
        parameters: [
            EffectParameter(id: Param.size, name: "Size", group: "Impact Ring", defaultValue: .number(90), range: 4...800, step: 1, unit: "px"),
            EffectParameter(id: Param.thickness, name: "Thickness", group: "Impact Ring", defaultValue: .number(0.08), range: 0.01...0.5, step: 0.01, presentation: .slider),
            EffectParameter(id: Param.duration, name: "Duration", group: "Impact Ring", defaultValue: .number(400), range: 50...3000, step: 10, unit: "ms"),
            EffectParameter(id: Param.minSpeed, name: "Min Speed", group: "Impact Ring", defaultValue: .number(150), range: 0...3000, step: 10, unit: "px/s"),
            EffectParameter(id: Param.colour, name: "Colour", group: "Impact Ring", defaultValue: .color(EffectColor(r: 255, g: 255, b: 255))),
            EffectParameter(id: Param.additive, name: "Additive", group: "Impact Ring", defaultValue: .toggle(true)),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 2 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let size = context.number(Param.size)
        let path = BuiltInSprite.hoop(thickness: context.number(Param.thickness))
        let duration = context.number(Param.duration)
        let minSpeed = context.number(Param.minSpeed)
        let colour = context.color(Param.colour)
        let additive = context.toggle(Param.additive)
        // A hoop is drawn at 512.
        let scale = size / 512

        var rings: [StoryboardSprite] = []
        for (index, sprite) in sprites.enumerated() {
            guard rings.count < Self.maximumTotal else { break }
            let landings = sprite.commands.compactMap { command -> (x: Double, y: Double, at: Double)? in
                guard command.endTime > command.startTime else { return nil }
                let seconds = (command.endTime - command.startTime) / 1000
                switch command.payload {
                case let .move(sx, sy, ex, ey):
                    return hypot(ex - sx, ey - sy) / seconds >= minSpeed ? (ex, ey, command.endTime) : nil
                case let .moveX(s, e):
                    return abs(e - s) / seconds >= minSpeed ? (e, sprite.defaultY, command.endTime) : nil
                case let .moveY(s, e):
                    return abs(e - s) / seconds >= minSpeed ? (sprite.defaultX, e, command.endTime) : nil
                default:
                    return nil
                }
            }
            // A chain of moves is one path: only where it stops is a landing.
            let ends = Set(sprite.commands.filter(\.isPosition).map(\.startTime))
            for (k, landing) in landings.filter({ !ends.contains($0.at) }).prefix(Self.maximumPerSprite).enumerated() {
                var ring = StoryboardSprite(
                    id: "\(context.idPrefix)/r\(index)/\(k)", layer: sprite.layer, origin: .centre,
                    filePath: path, defaultX: landing.x, defaultY: landing.y,
                )
                let end = landing.at + duration
                ring.commands = [
                    Command(easing: .quadOut, startTime: landing.at, endTime: end, payload: .scale(start: scale * 0.2, end: scale)),
                    Command(easing: .quadOut, startTime: landing.at, endTime: end, payload: .fade(start: 1, end: 0)),
                ]
                if colour.r != 255 || colour.g != 255 || colour.b != 255 {
                    ring.commands.append(Command(easing: .linear, startTime: landing.at, endTime: landing.at, payload: .color(
                        startR: colour.r, startG: colour.g, startB: colour.b, endR: colour.r, endG: colour.g, endB: colour.b,
                    )))
                }
                if additive {
                    ring.commands.append(Command(easing: .linear, startTime: landing.at, endTime: end, payload: .parameter(.additive)))
                }
                rings.append(ring)
            }
        }
        return sprites + rings.prefix(Self.maximumTotal)
    }

    public func duration(of clipDuration: Double, in context: FilterContext) -> Double {
        // A move that lands at the very end rings past the clip.
        clipDuration + context.number(Param.duration)
    }
}
