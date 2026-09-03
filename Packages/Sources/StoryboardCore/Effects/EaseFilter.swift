import Foundation

/// Replaces the curve on every command a clip writes.
///
/// The most underrated filter here, and free: not one sprite added, not one
/// command more. An emitter interpolates linearly because that is the only
/// honest default for something it knows nothing about — and linear is the one
/// curve nothing in the world actually follows. Everything real starts slowly,
/// or arrives and settles, or overshoots and comes back.
///
/// Applied to a whole clip at once it is the difference between motion that
/// looks calculated and motion that looks intended.
public struct EaseFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let curve = "curve"
        public static let motionOnly = "motionOnly"
    }

    /// The curves worth offering, named for what they do rather than for their
    /// polynomial.
    ///
    /// A short list on purpose: the format has thirty-five, and a menu of
    /// thirty-five is a menu nobody reads. These are the shapes that change how
    /// a movement *reads*; the rest are variations in degree.
    public enum Curve: String, CaseIterable, Sendable {
        case linear = "Linear"
        case ease = "Ease In Out"
        case accelerate = "Accelerate"
        case settle = "Settle"
        case overshoot = "Overshoot"
        case anticipate = "Anticipate"
        case bounce = "Bounce"
        case elastic = "Elastic"

        var easing: Easing {
            switch self {
            case .linear: .linear
            case .ease: .quadInOut
            case .accelerate: .quadIn
            case .settle: .quadOut
            case .overshoot: .backOut
            case .anticipate: .backIn
            case .bounce: .bounceOut
            case .elastic: .elasticOut
            }
        }
    }

    public static let descriptor = FilterDescriptor(
        type: "ease",
        name: "Ease",
        category: .motion,
        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
        parameters: [
            EffectParameter(
                id: Param.curve,
                name: "Curve",
                group: "Ease",
                defaultValue: .choice(Curve.settle.rawValue),
                options: Curve.allCases.map(\.rawValue),
            ),
            // On by default, because the curves that make movement read well
            // make fades read badly: a bouncing opacity flickers, and an
            // elastic one flashes past full brightness and back.
            EffectParameter(
                id: Param.motionOnly,
                name: "Movement Only",
                group: "Ease",
                defaultValue: .toggle(true),
            ),
        ],
    )

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let curve = Curve(rawValue: context.choice(Param.curve)) ?? .settle
        let motionOnly = context.toggle(Param.motionOnly)
        let easing = curve.easing

        return sprites.map { sprite in
            var eased = sprite
            eased.commands = sprite.commands.map { command in
                guard applies(to: command.kind, motionOnly: motionOnly) else { return command }
                var curved = command
                curved.timing.easing = easing
                return curved
            }
            eased.loops = sprite.loops.map { loop in
                var curved = loop
                curved.commands = loop.commands.map { command in
                    guard applies(to: command.kind, motionOnly: motionOnly) else { return command }
                    var inner = command
                    inner.timing.easing = easing
                    return inner
                }
                return curved
            }
            return eased
        }
    }

    private func applies(to kind: CommandKind, motionOnly: Bool) -> Bool {
        switch kind {
        case .move, .moveX, .moveY, .scale, .vectorScale, .rotate:
            true
        case .fade, .color:
            !motionOnly
        // A flag has no interpolation to curve.
        case .parameter:
            false
        }
    }
}
