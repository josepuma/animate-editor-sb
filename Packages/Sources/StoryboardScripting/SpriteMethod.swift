import Foundation

/// Every chaining method a script's sprite builder answers to.
///
/// One list, because the surface is described in three places that have to
/// agree: the real builder registers them, the inert builder handed out past
/// the sprite ceiling has to accept the same set, and the generated type
/// declarations tell the editor what exists. Written out by hand in each,
/// they drift — and this project has already shipped that bug once, when the
/// completion table carried all thirty-five easing names backwards and a script
/// animated as `linear` in silence because a name the runtime rejects arrives
/// as `undefined`, becomes NaN, and is clamped to zero.
///
/// Adding a case is what makes a new method reachable from a script *and*
/// declared to the editor *and* safe past the ceiling. There is a test over
/// `allCases` for each of those three, so a method added to one place and
/// forgotten in another fails on arrival rather than in someone's project.
public enum SpriteMethod: String, CaseIterable, Sendable {
    case fade
    case move
    case scale
    case rotate
    case moveX
    case moveY
    /// `_V` — the two axes set separately, without which a letterbox bar
    /// cannot be written at all.
    case scaleVec
    /// `_C` — channels in [0, 255], as the format has them.
    case color
    /// Not a command: it sets where the sprite sits when nothing moves it.
    case at
    /// `_P` — the flags, which take a span rather than values.
    case additive
    case flipH
    case flipV

    /// How many numbers the method reads after an optional easing.
    ///
    /// `at` is the odd one out: it is a position rather than a command, so it
    /// takes exactly two numbers and no timing at all. The flags take a span
    /// with no values, which is why zero is a real answer here rather than a
    /// stand-in for "unknown".
    public var valueCount: Int {
        switch self {
        case .fade, .scale, .rotate, .moveX, .moveY: 2
        case .move, .scaleVec: 4
        case .color: 6
        case .at: 2
        case .additive, .flipH, .flipV: 0
        }
    }

    /// Whether the method carries a start and end time.
    ///
    /// Only `at` does not. It exists so a caller can build an argument list
    /// without special-casing the one exception at every site.
    public var isTimed: Bool { self != .at }

    /// A call that satisfies the method's arity, for tests and examples.
    ///
    /// Kept beside the arity it derives from so the two cannot disagree: a
    /// sample list written separately would go stale the moment a method's
    /// value count changed, and a test calling a method with the wrong number
    /// of arguments fails for a reason that has nothing to do with what it is
    /// checking.
    public var sampleArguments: String {
        let timing = isTimed ? ["0", "10"] : []
        let values = (0 ..< valueCount).map { _ in "1" }
        return (timing + values).joined(separator: ", ")
    }
}
