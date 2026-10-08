import Foundation

/// Cuts each sprite into horizontal bands that jump sideways on their own — a
/// signal tearing.
///
/// Each band is a derived image the size of the original with only its strip
/// left, so at rest they line up into the sprite. Every step a band either
/// holds or jumps, independently of the others: bands moving together read as
/// a shake, apart as the picture coming apart. A jump is a zero-length
/// command, held until the next — a glitch snaps, it never slides.
public struct SliceGlitchFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let slices = "slices"
        public static let amount = "amount"
        public static let rate = "rate"
        public static let chance = "chance"
    }

    /// Jumps per band, at most; past this the steps lengthen.
    static let maximumSteps = 64

    public static let descriptor = FilterDescriptor(
        type: "slice-glitch",
        name: "Slice Glitch",
        category: .destroy,
        systemImage: "rectangle.split.3x1",
        parameters: [
            EffectParameter(id: Param.slices, name: "Slices", group: "Slice Glitch", defaultValue: .integer(6), range: 2...16, step: 1),
            EffectParameter(id: Param.amount, name: "Amount", group: "Slice Glitch", defaultValue: .number(24), range: 0...400, step: 1, unit: "px"),
            EffectParameter(id: Param.rate, name: "Rate", group: "Slice Glitch", defaultValue: .number(8), range: 1...30, step: 1, unit: "/s"),
            EffectParameter(
                id: Param.chance, name: "Chance", group: "Slice Glitch",
                // Most steps quiet: the calm between bursts is what makes each
                // one an event.
                defaultValue: .number(0.4), range: 0...1, step: 0.05, presentation: .slider,
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        Double(max(2, context.integer(Param.slices)))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let amount = context.number(Param.amount)
        let chance = context.number(Param.chance)
        guard amount > 0, chance > 0 else { return sprites }
        let slices = min(max(2, context.integer(Param.slices)), DerivedSprite.tileRange.upperBound)
        let step = 1000 / max(context.number(Param.rate), 1)
        let root = FilterParticles.stream(context)

        return sprites.enumerated().flatMap { index, sprite -> [StoryboardSprite] in
            guard !sprite.loops.contains(where: { $0.commands.contains(where: \.isPosition) }),
                  let prepared = StoryboardResolver.prepare([sprite]).first, prepared.activeStart.isFinite
            else { return [sprite] }
            let birth = prepared.activeStart
            let death = prepared.activeEnd
            let span = max(death - birth, 0)
            let count = min(max(Int((span / step).rounded(.up)), 1), Self.maximumSteps)
            // By index, never by adding a step.
            let times = (0...count).map { $0 == count ? death : birth + span * Double($0) / Double(count) }
            let base = times.map { StoryboardResolver.state(of: prepared, at: $0) }

            return (0..<slices).map { slice in
                var stream = root.stream(index * DerivedSprite.tileRange.upperBound + slice)
                var band = sprite
                band.id = "\(context.idPrefix)/g\(index)/\(slice)"
                band.filePath = DerivedSprite.tiled(sprite.filePath, columns: 1, rows: slices, index: slice)
                band.commands.removeAll(where: \.isPosition)
                band.defaultX = base[0].x
                band.defaultY = base[0].y
                // The direction of a band's sideways is the sprite's own x,
                // turned with it.
                for (time, state) in zip(times, base) {
                    let jump = stream.unit() < chance ? stream.symmetric(amount) : 0
                    let x = state.x + jump * cos(state.rotation)
                    let y = state.y + jump * sin(state.rotation)
                    band.commands.append(Command(easing: .linear, startTime: time, endTime: time, payload: .move(
                        startX: x, startY: y, endX: x, endY: y,
                    )))
                }
                return band
            }
        }
    }
}
