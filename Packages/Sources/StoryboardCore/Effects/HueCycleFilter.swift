import Foundation

/// Every sprite on the clip running around the colour wheel.
///
/// Tint ramps between two colours once; this keeps going, and `Spread` starts
/// each sprite somewhere else on the wheel so a field reads as a rainbow
/// travelling through it rather than one colour blinking.
///
/// One sprite in, one out: it replaces the sprite's `_C`, like Tint, because a
/// cycle on top of another colour would fight it command for command.
public struct HueCycleFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let speed = "speed"
        public static let phase = "phase"
        public static let spread = "spread"
        public static let saturation = "saturation"
        public static let brightness = "brightness"
    }

    /// Commands per sprite, at most. A long life at a high speed would write
    /// thousands; past this the steps lengthen instead — never cut, since a
    /// cut leaves the last stretch holding one colour for the rest of the life.
    public static let maximumSteps = 96

    public static let descriptor = FilterDescriptor(
        type: "hue-cycle",
        name: "Hue Cycle",
        category: .look,
        systemImage: "paintpalette.fill",
        parameters: [
            EffectParameter(
                id: Param.speed, name: "Speed", group: "Hue Cycle",
                defaultValue: .number(0.5), range: 0.05...4, step: 0.05, unit: "/s",
            ),
            EffectParameter(
                id: Param.phase, name: "Start Hue", group: "Hue Cycle",
                defaultValue: .number(0), range: 0...1, step: 0.01, presentation: .slider,
            ),
            EffectParameter(
                id: Param.spread, name: "Spread", group: "Hue Cycle",
                defaultValue: .number(0.25), range: 0...1, step: 0.05, presentation: .slider,
            ),
            EffectParameter(
                id: Param.saturation, name: "Saturation", group: "Hue Cycle",
                defaultValue: .number(0.8), range: 0...1, step: 0.05, presentation: .slider,
            ),
            EffectParameter(
                id: Param.brightness, name: "Brightness", group: "Hue Cycle",
                defaultValue: .number(1), range: 0...1, step: 0.05, presentation: .slider,
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let speed = max(context.number(Param.speed), 0.0001)
        let phase = context.number(Param.phase)
        let spread = context.number(Param.spread)
        let saturation = context.number(Param.saturation)
        let brightness = context.number(Param.brightness)
        let last = Double(max(sprites.count - 1, 1))

        return sprites.enumerated().map { index, sprite in
            // In turns of the wheel, against clip time: every sprite shares one
            // clock, so a spread field moves as a band rather than each
            // particle restarting its own cycle when it is born.
            let start = phase + spread * Double(index) / last
            let hue = { (time: Double) in start + speed * time / 1000 }

            var cycled = sprite
            cycled.commands.removeAll { $0.kind == .color }
            let birth = sprite.commands.map(\.startTime).min() ?? 0
            let death = sprite.commands.map(\.endTime).max() ?? birth

            let colour = { (time: Double) in
                Self.rgb(hue: hue(time), saturation: saturation, brightness: brightness)
            }
            let cuts = Self.breaks(birth, death, hue: hue, speed: speed, start: start)
            for (from, to) in zip(cuts, cuts.dropFirst()) {
                let a = colour(from)
                let b = colour(to)
                cycled.commands.append(Command(
                    easing: .linear, startTime: from, endTime: to,
                    payload: .color(startR: a.r, startG: a.g, startB: a.b, endR: b.r, endG: b.g, endB: b.b),
                ))
            }
            if birth == death {
                let a = colour(birth)
                cycled.commands.append(Command(
                    easing: .linear, startTime: birth, endTime: birth,
                    payload: .color(startR: a.r, startG: a.g, startB: a.b, endR: a.r, endG: a.g, endB: a.b),
                ))
            }
            return cycled
        }
    }

    /// Where the colour commands cut: every sixth of the wheel the hue crosses.
    ///
    /// HSV is linear in RGB between the six primaries and secondaries, so a
    /// straight `_C` between two of them is the wheel exactly — the ramp needs
    /// no sampling. Past ``maximumSteps`` the life is cut evenly instead.
    static func breaks(
        _ birth: Double, _ death: Double,
        hue: (Double) -> Double, speed: Double, start: Double,
    ) -> [Double] {
        guard death > birth else { return [birth] }

        let first = (hue(birth) * 6).rounded(.down) + 1
        let lastCrossing = (hue(death) * 6).rounded(.up) - 1
        let crossings = max(0, Int(lastCrossing - first) + 1)

        guard crossings + 1 <= maximumSteps else {
            let step = (death - birth) / Double(maximumSteps)
            return (0...maximumSteps).map { index in
                index == maximumSteps ? death : birth + step * Double(index)
            }
        }

        var times = [birth]
        var k = first
        while k <= lastCrossing {
            // The time this sixth is crossed, by index rather than by adding
            // a step: an accumulated step drifts, and two colour commands
            // overlapping by a hair are two commands fighting.
            let time = (k / 6 - start) * 1000 / speed
            if time > birth, time < death { times.append(time) }
            k += 1
        }
        times.append(death)
        return times
    }

    /// HSV to the 0–255 channels `_C` takes.
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double) {
        let h = (hue - hue.rounded(.down)) * 6
        let sector = min(Int(h), 5)
        let f = h - Double(sector)
        let v = brightness * 255
        let p = v * (1 - saturation)
        let q = v * (1 - saturation * f)
        let t = v * (1 - saturation * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch sector {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return (r.rounded(), g.rounded(), b.rounded())
    }
}
