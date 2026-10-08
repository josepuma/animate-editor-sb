import Foundation

/// Starts each sprite on the clip a little later than the last, so the clip
/// arrives as a wave instead of all at once — After Effects' sequence layers,
/// for anything.
///
/// The spread is a **total**, not a delay per sprite: forty milliseconds each
/// is a beat over a line of text and eighty seconds over an emitter of two
/// thousand. A total keeps the same feel whatever the clip holds.
///
/// Every command moves, loops included — a sprite plays its whole life later,
/// unchanged. The clip runs on by the spread, and says so.
public struct StaggerFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let spread = "spread"
        public static let order = "order"
    }

    public enum Order: String, CaseIterable, Sendable {
        case index = "In Order"
        case reverse = "Reverse"
        case leftToRight = "Left to Right"
        case topToBottom = "Top to Bottom"
        case fromCentre = "From Centre"
        case random = "Random"
    }

    public static let descriptor = FilterDescriptor(
        type: "stagger",
        name: "Stagger",
        category: .time,
        systemImage: "chart.bar.doc.horizontal",
        parameters: [
            EffectParameter(
                id: Param.spread, name: "Spread", group: "Stagger",
                defaultValue: .number(600), range: 0...10000, step: 10, unit: "ms",
            ),
            EffectParameter(
                id: Param.order, name: "Order", group: "Stagger",
                defaultValue: .choice(Order.index.rawValue), options: Order.allCases.map(\.rawValue),
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func duration(of clipDuration: Double, in context: FilterContext) -> Double {
        clipDuration + max(0, context.number(Param.spread))
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let spread = max(0, context.number(Param.spread))
        guard spread > 0, sprites.count > 1 else { return sprites }
        let order = Order(rawValue: context.choice(Param.order)) ?? .index

        let ranks = Self.ranks(of: sprites, order: order, seed: NoiseField.seed(context.idPrefix))
        let last = Double(max(ranks.max() ?? 0, 1))
        return zip(sprites, ranks).map { sprite, rank in
            Self.shifted(sprite, by: spread * Double(rank) / last)
        }
    }

    /// A dense rank per sprite: ties share one, so two sprites at the same x
    /// arrive together instead of in whatever order they happened to be in.
    static func ranks(of sprites: [StoryboardSprite], order: Order, seed: UInt64) -> [Int] {
        let keys: [Double] = switch order {
        case .index: sprites.indices.map(Double.init)
        case .reverse: sprites.indices.map { Double(sprites.count - 1 - $0) }
        case .leftToRight: sprites.map { start(of: $0).x }
        case .topToBottom: sprites.map { start(of: $0).y }
        case .fromCentre: sprites.map {
                let point = start(of: $0)
                return hypot(point.x - StageSnap.Stage.centreX, point.y - StageSnap.Stage.centreY)
            }
        case .random: shuffled(count: sprites.count, seed: seed).map(Double.init)
        }
        let distinct = Array(Set(keys)).sorted()
        return keys.map { key in distinct.firstIndex(of: key) ?? 0 }
    }

    /// Where a sprite is when it is born, as the resolver draws it.
    private static func start(of sprite: StoryboardSprite) -> (x: Double, y: Double) {
        guard let prepared = StoryboardResolver.prepare([sprite]).first, prepared.activeStart.isFinite
        else { return (sprite.defaultX, sprite.defaultY) }
        let state = StoryboardResolver.state(of: prepared, at: prepared.activeStart)
        return (state.x, state.y)
    }

    /// A seeded permutation of `0..<count`: a rank for each index.
    private static func shuffled(count: Int, seed: UInt64) -> [Int] {
        var rng = EffectRandom(seed: seed)
        var ranks = Array(0..<count)
        for index in stride(from: count - 1, to: 0, by: -1) {
            ranks.swapAt(index, Int(rng.next() % UInt64(index + 1)))
        }
        return ranks
    }

    private static func shifted(_ sprite: StoryboardSprite, by delay: Double) -> StoryboardSprite {
        guard delay > 0 else { return sprite }
        var moved = sprite
        moved.commands = sprite.commands.map { command in
            Command(
                easing: command.easing,
                startTime: command.startTime + delay, endTime: command.endTime + delay,
                payload: command.payload,
            )
        }
        // A loop's body is relative to its start, so only the start moves.
        moved.loops = sprite.loops.map { loop in
            var later = loop
            later.startTime += delay
            return later
        }
        return moved
    }
}
