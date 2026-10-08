import Foundation

/// Stretches each sprite along the way it is moving, thinning it to keep its
/// area — the oldest rule in animation, and the cheapest way to make motion
/// read as weight.
///
/// Read from the sprite's real velocity, sampled with the resolver that draws
/// it, so it follows whatever made the sprite move: an emitter's gravity, a
/// script, keyframes. Written as `_V`, replacing the sprite's own scale and
/// multiplying it — a sprite drawn at 2×0.5 stretches from 2×0.5.
///
/// Stretches on screen axes. A rotated sprite stretches across its own image
/// rather than along its path; aligning it would mean turning the sprite,
/// which is a decision about the clip, not about its squash.
public struct SquashStretchFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let amount = "amount"
        public static let fullAt = "fullAt"
        public static let rate = "rate"
    }

    /// Scale commands per sprite, at most; past this the steps lengthen.
    static let maximumSteps = 48

    public static let descriptor = FilterDescriptor(
        type: "squash-stretch",
        name: "Squash & Stretch",
        category: .motion,
        systemImage: "arrow.left.and.right.square",
        parameters: [
            EffectParameter(
                id: Param.amount, name: "Amount", group: "Squash & Stretch",
                defaultValue: .number(0.4), range: 0...1.5, step: 0.05, presentation: .slider,
            ),
            EffectParameter(
                id: Param.fullAt, name: "Full At", group: "Squash & Stretch",
                // The speed that earns the whole stretch: slower moves stretch
                // in proportion, faster ones are capped there.
                defaultValue: .number(800), range: 50...5000, step: 50, unit: "px/s",
            ),
            EffectParameter(id: Param.rate, name: "Sample Rate", group: "Squash & Stretch", defaultValue: .number(15), range: 2...30, step: 1, unit: "/s"),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let amount = context.number(Param.amount)
        guard amount > 0 else { return sprites }
        let fullAt = max(context.number(Param.fullAt), 1)
        let rate = context.number(Param.rate)
        return sprites.map { stretched($0, amount: amount, fullAt: fullAt, rate: rate) }
    }

    private func stretched(_ sprite: StoryboardSprite, amount: Double, fullAt: Double, rate: Double) -> StoryboardSprite {
        guard !sprite.loops.contains(where: { $0.commands.contains(where: { $0.kind == .scale || $0.kind == .vectorScale }) }),
              let prepared = StoryboardResolver.prepare([sprite]).first,
              prepared.activeStart.isFinite, prepared.activeEnd > prepared.activeStart
        else { return sprite }

        let birth = prepared.activeStart
        let death = prepared.activeEnd
        let span = death - birth
        let steps = min(max(Int((span * rate / 1000).rounded(.up)), 1), Self.maximumSteps)
        let times = (0...steps).map { $0 == steps ? death : birth + span * Double($0) / Double(steps) }

        // Velocity over a short window either side, clamped to the life:
        // the resolver holds a sprite's ends, so a window past them reads as
        // standing still rather than as a jump.
        let window = 8.0
        let velocity = { (time: Double) -> (x: Double, y: Double) in
            let a = max(birth, time - window)
            let b = min(death, time + window)
            guard b > a else { return (0, 0) }
            let p = StoryboardResolver.state(of: prepared, at: a)
            let q = StoryboardResolver.state(of: prepared, at: b)
            return ((q.x - p.x) / (b - a) * 1000, (q.y - p.y) / (b - a) * 1000)
        }

        let samples = times.map { time -> (x: Double, y: Double) in
            let state = StoryboardResolver.state(of: prepared, at: time)
            let v = velocity(time)
            let ex = amount * min(abs(v.x) / fullAt, 1)
            let ey = amount * min(abs(v.y) / fullAt, 1)
            // Area kept: whatever one axis gains, the other gives back.
            let factor = ((1 + ex) / (1 + ey)).squareRoot()
            return (state.scaleX * factor, state.scaleY / factor)
        }
        let rest = StoryboardResolver.state(of: prepared, at: birth)
        let moves = samples.contains { abs($0.x - rest.scaleX) > 1e-6 || abs($0.y - rest.scaleY) > 1e-6 }
        guard moves else { return sprite }

        var result = sprite
        result.commands.removeAll { $0.kind == .scale || $0.kind == .vectorScale }
        for index in 1..<samples.count {
            let from = samples[index - 1]
            let to = samples[index]
            result.commands.append(Command(
                easing: .linear, startTime: times[index - 1], endTime: times[index],
                payload: .vectorScale(startX: from.x, startY: from.y, endX: to.x, endY: to.y),
            ))
        }
        return result
    }
}
