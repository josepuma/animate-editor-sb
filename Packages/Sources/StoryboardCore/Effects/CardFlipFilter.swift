import Foundation

/// Turns each sprite over like a card — or the whole clip like one card.
///
/// osu! has no 3D, but a card turning about its vertical axis is, seen from
/// in front, an image narrowing to nothing and widening again mirrored: the
/// width is the cosine of the angle, and past 90° the back shows. That is a
/// `_V` and a flip, both of which a sprite has.
///
/// `Per Sprite` turns every sprite in place — letters flipping one by one.
/// `As Group` also folds positions about the clip's pivot, so the clip turns
/// as one board; osu! has no nested sprites, so the group is baked into each.
public struct CardFlipFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let axis = "axis"
        public static let mode = "mode"
        public static let turns = "turns"
        public static let start = "start"
        public static let duration = "duration"
        public static let easing = "easing"
    }

    public enum Axis: String, CaseIterable, Sendable {
        case y = "Vertical (Y)"
        case x = "Horizontal (X)"
    }

    public enum Mode: String, CaseIterable, Sendable {
        case sprite = "Per Sprite"
        case group = "As Group"
    }

    /// Monotonic curves only: the crossings where the card goes edge-on are
    /// found by inverting the curve, and one that overshoots crosses back.
    public enum Curve: String, CaseIterable, Sendable {
        case linear = "Linear"
        case smooth = "Ease In Out"
        case out = "Ease Out"

        var easing: Easing {
            switch self {
            case .linear: .linear
            case .smooth: .sineInOut
            case .out: .quadOut
            }
        }
    }

    public static let descriptor = FilterDescriptor(
        type: "card-flip",
        name: "Card Flip",
        category: .threeD,
        systemImage: "rectangle.portrait.rotate",
        parameters: [
            EffectParameter(id: Param.axis, name: "Axis", group: "Card Flip", defaultValue: .choice(Axis.y.rawValue), options: Axis.allCases.map(\.rawValue)),
            EffectParameter(id: Param.mode, name: "Turn", group: "Card Flip", defaultValue: .choice(Mode.sprite.rawValue), options: Mode.allCases.map(\.rawValue)),
            EffectParameter(
                id: Param.turns, name: "Half Turns", group: "Card Flip",
                // One half-turn lands on the back, two come round to the
                // front again.
                defaultValue: .number(2), range: 0...8, step: 1,
            ),
            EffectParameter(id: Param.start, name: "Start", group: "Card Flip", defaultValue: .number(0), range: 0...60000, step: 10, unit: "ms"),
            EffectParameter(id: Param.duration, name: "Duration", group: "Card Flip", defaultValue: .number(800), range: 50...20000, step: 10, unit: "ms"),
            EffectParameter(id: Param.easing, name: "Curve", group: "Card Flip", defaultValue: .choice(Curve.smooth.rawValue), options: Curve.allCases.map(\.rawValue)),
        ],
    )

    /// Samples per half-turn inside the flip: the width is a cosine, and
    /// eight chords keep it within a couple of percent of the curve.
    static let samplesPerHalfTurn = 8

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let turns = context.number(Param.turns)
        guard turns > 0 else { return sprites }
        let start = context.number(Param.start)
        let duration = max(context.number(Param.duration), 1)
        let curve = (Curve(rawValue: context.choice(Param.easing)) ?? .smooth).easing
        let vertical = (Axis(rawValue: context.choice(Param.axis)) ?? .y) == .y
        let group = (Mode(rawValue: context.choice(Param.mode)) ?? .sprite) == .group
        let pivot = (x: context.transform[value: .x], y: context.transform[value: .y])

        let angle = { (time: Double) -> Double in
            let progress = min(max((time - start) / duration, 0), 1)
            return turns * .pi * applyEasing(curve, progress)
        }

        // The flip itself, densely, plus every edge-on moment, so the side
        // that faces is constant across each interval.
        let steps = min(max(Int((turns * Double(Self.samplesPerHalfTurn)).rounded(.up)), 2), 96)
        var times = (0...steps).map { start + duration * Double($0) / Double(steps) }
        times += Self.edgeOn(turns: turns, start: start, duration: duration, curve: curve)

        return sprites.map { sprite in
            StateResample.rewrite(sprite, at: StateResample.boundaries(of: sprite) + times) { frame, time in
                let c = cos(angle(time))
                var turned = frame
                if vertical {
                    turned.scaleX = frame.scaleX * abs(c)
                    turned.flipH = frame.flipH != (c < 0)
                    if group { turned.x = pivot.x + (frame.x - pivot.x) * c }
                } else {
                    turned.scaleY = frame.scaleY * abs(c)
                    turned.flipV = frame.flipV != (c < 0)
                    if group { turned.y = pivot.y + (frame.y - pivot.y) * c }
                }
                return turned
            }
        }
    }

    /// The moments the card is edge-on: the angle at an odd quarter-turn,
    /// found by inverting the curve with bisection.
    static func edgeOn(turns: Double, start: Double, duration: Double, curve: Easing) -> [Double] {
        var found: [Double] = []
        var k = 0.5
        while k < turns {
            let target = k / turns
            var low = 0.0
            var high = 1.0
            for _ in 0..<40 {
                let middle = (low + high) / 2
                if applyEasing(curve, middle) < target { low = middle } else { high = middle }
            }
            found.append(start + duration * (low + high) / 2)
            k += 1
        }
        return found
    }
}
