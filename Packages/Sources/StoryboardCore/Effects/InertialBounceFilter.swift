import Foundation

/// When a move ends, the sprite carries on past it and springs back, settling
/// in a few decaying swings — After Effects' most-used expression, as a filter.
///
/// The momentum is the move's average speed, not its speed at the last
/// instant: an eased-out move lands with none, and a bounce that only reacted
/// to linear keys would do nothing on most clips. Each swing is one command
/// from crest to crest with a sine ease, so a bounce costs a handful of lines,
/// not a sampled curve.
///
/// A bounce lives only in the gap a move leaves: never over the next command
/// of the same property (osu! would let one of the two win) and never past
/// the sprite's life, which would keep it alive invisibly and lengthen nothing
/// anyone sees.
public struct InertialBounceFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let amount = "amount"
        public static let frequency = "frequency"
        public static let decay = "decay"
        public static let target = "target"
    }

    public enum Target: String, CaseIterable, Sendable {
        case all = "All"
        case position = "Position"
        case scale = "Scale"
        case rotation = "Rotation"
    }

    /// Half-swings per bounce, at most: past this the motion is too small to
    /// see and every one is a command per sprite.
    static let maximumSwings = 8

    public static let descriptor = FilterDescriptor(
        type: "inertial-bounce",
        name: "Inertial Bounce",
        category: .motion,
        systemImage: "arrow.down.right.and.arrow.up.left",
        parameters: [
            EffectParameter(
                id: Param.target, name: "Apply To", group: "Inertial Bounce",
                defaultValue: .choice(Target.all.rawValue), options: Target.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: Param.amount, name: "Amount", group: "Inertial Bounce",
                defaultValue: .number(1), range: 0...3, step: 0.05, presentation: .slider,
            ),
            EffectParameter(
                id: Param.frequency, name: "Frequency", group: "Inertial Bounce",
                defaultValue: .number(3), range: 0.5...12, step: 0.5, unit: "Hz",
            ),
            EffectParameter(
                id: Param.decay, name: "Decay", group: "Inertial Bounce",
                defaultValue: .number(6), range: 0.5...20, step: 0.5, unit: "/s",
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let amount = context.number(Param.amount)
        guard amount > 0 else { return sprites }
        let spring = Spring(
            amount: amount,
            omega: 2 * .pi * context.number(Param.frequency),
            decay: context.number(Param.decay),
        )
        let target = Target(rawValue: context.choice(Param.target)) ?? .all
        let families: [[CommandKind]] = switch target {
        case .all: [[.move, .moveX, .moveY], [.scale, .vectorScale], [.rotate]]
        case .position: [[.move, .moveX, .moveY]]
        case .scale: [[.scale, .vectorScale]]
        case .rotation: [[.rotate]]
        }

        return sprites.map { sprite in
            let death = sprite.commands.map(\.endTime).max() ?? 0
            var bounced = sprite
            for family in families {
                let members = sprite.commands.filter { family.contains($0.kind) }
                for (index, command) in members.enumerated() {
                    let next = members.enumerated()
                        .filter { $0.offset != index && $0.element.startTime >= command.endTime }
                        .map(\.element.startTime).min()
                    let limit = min(next ?? death, death)
                    bounced.commands += spring.tail(after: command, until: limit)
                }
            }
            return bounced
        }
    }
}

/// A damped swing: offset(τ) = A·sin(ωτ)·e^(−kτ), with A set so the swing
/// leaves at the move's own speed times `amount`.
private struct Spring {
    let amount: Double
    let omega: Double
    let decay: Double

    /// The swings after `command`, ending back on its end value, all before
    /// `limit`. Empty when not even one full swing fits.
    func tail(after command: Command, until limit: Double) -> [Command] {
        let duration = command.endTime - command.startTime
        guard duration > 0, omega > 0 else { return [] }
        let ends = command.payload.ends
        guard !ends.isEmpty else { return [] }
        // Per second, so the amplitude comes out in the property's own units.
        let speeds = ends.map { ($0.end - $0.start) / (duration / 1000) }
        guard speeds.contains(where: { $0 != 0 }) else { return [] }

        // Crests sit where the damped sine turns: tan(ωτ) = ω/k.
        let first = atan2(omega, decay) / omega
        let half = Double.pi / omega
        let zeroAfter = { (n: Int) in Double(n + 1) * half }

        var times: [Double] = [0]
        var swing = 0
        while swing < InertialBounceFilter.maximumSwings {
            let crest = first + Double(swing) * half
            // A crest is only worth writing if the return to rest after it
            // still fits; otherwise stop at the last rest point.
            guard command.endTime + zeroAfter(swing) * 1000 <= limit else { break }
            times.append(crest)
            swing += 1
            if exp(-decay * crest) < 0.03 { break }
        }
        guard swing > 0 else { return [] }
        // Back to rest at the zero after the last crest written.
        times.append(zeroAfter(swing - 1))

        let offset = { (tau: Double, speed: Double) -> Double in
            tau == times.last ? 0 : speed * amount / omega * sin(omega * tau) * exp(-decay * tau)
        }
        let value = { (tau: Double) -> [Double] in
            zip(ends, speeds).map { $0.end + offset(tau, $1) }
        }

        var tail: [Command] = []
        for index in 1..<times.count {
            let from = times[index - 1]
            let to = times[index]
            // Out of the move at speed, crest to crest eased both ways.
            let easing: Easing = index == 1 ? .sineOut : (index == times.count - 1 ? .sineIn : .sineInOut)
            tail.append(Command(
                easing: easing,
                startTime: command.endTime + from * 1000,
                endTime: command.endTime + to * 1000,
                payload: command.payload.with(start: value(from), end: value(to)),
            ))
        }
        return tail
    }
}

private extension Command.Payload {
    /// Each animated component's two ends, in a fixed order `with` reads back.
    var ends: [(start: Double, end: Double)] {
        switch self {
        case let .move(sx, sy, ex, ey): [(sx, ex), (sy, ey)]
        case let .moveX(s, e), let .moveY(s, e), let .scale(s, e), let .rotate(s, e): [(s, e)]
        case let .vectorScale(sx, sy, ex, ey): [(sx, ex), (sy, ey)]
        default: []
        }
    }

    func with(start: [Double], end: [Double]) -> Command.Payload {
        switch self {
        case .move: .move(startX: start[0], startY: start[1], endX: end[0], endY: end[1])
        case .moveX: .moveX(start: start[0], end: end[0])
        case .moveY: .moveY(start: start[0], end: end[0])
        case .scale: .scale(start: start[0], end: end[0])
        case .rotate: .rotate(start: start[0], end: end[0])
        case .vectorScale: .vectorScale(startX: start[0], startY: start[1], endX: end[0], endY: end[1])
        default: self
        }
    }
}
