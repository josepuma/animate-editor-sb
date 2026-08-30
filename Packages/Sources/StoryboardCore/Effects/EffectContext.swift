import Foundation

/// Everything an effect is handed when it is asked to produce sprites.
///
/// Time is local: an effect generates over `0...duration` and never reads its
/// own placement. The offset is applied once, afterwards, by the evaluator —
/// which is what makes dragging a block on the timeline move its output rather
/// than regenerate it.
public struct EffectContext: Sendable {
    public let descriptor: EffectDescriptor
    public let node: EffectNode
    /// How long the effect runs, in milliseconds.
    public let duration: Double
    /// Prefix for generated sprite ids, keeping two nodes of the same effect
    /// from colliding.
    public let idPrefix: String

    private let values: [String: EffectValue]

    public init(descriptor: EffectDescriptor, node: EffectNode) {
        self.descriptor = descriptor
        self.node = node
        duration = max(0, node.duration)
        idPrefix = node.id

        // Reading through the declaration means a node saved before a
        // parameter existed still evaluates: the missing entry falls back to
        // its default instead of the effect having to check for nil.
        var resolved = descriptor.defaultValues
        for parameter in descriptor.parameters {
            if let stored = node.values[parameter.id] {
                resolved[parameter.id] = parameter.coerce(stored)
            }
        }
        values = resolved
    }

    // ─── Typed reads ─────────────────────────────────────────────────────────
    //
    // An effect asks for the type it needs and gets a usable value or the
    // declared default. Nothing downstream has to unwrap an optional, because
    // a parameter that is missing at this point is a bug in the declaration,
    // not a state the evaluator can do anything about.

    public func number(_ id: String) -> Double {
        switch values[id] {
        case let .number(value): value
        case let .integer(value): Double(value)
        default: 0
        }
    }

    public func integer(_ id: String) -> Int {
        switch values[id] {
        case let .integer(value): value
        case let .number(value): Int(value.rounded())
        default: 0
        }
    }

    public func toggle(_ id: String) -> Bool {
        if case let .toggle(value) = values[id] { return value }
        return false
    }

    public func choice(_ id: String) -> String {
        if case let .choice(value) = values[id] { return value }
        return ""
    }

    public func color(_ id: String) -> EffectColor {
        if case let .color(value) = values[id] { return value }
        return .white
    }

    public func text(_ id: String) -> String {
        if case let .text(value) = values[id] { return value }
        return ""
    }
}

/// An effect: a declaration plus a way to turn it into sprites.
///
/// The two halves are deliberately one protocol. An effect whose parameters
/// live apart from the code that reads them drifts — a renamed key compiles
/// fine and fails silently at evaluation.
public protocol Effect: Sendable {
    static var descriptor: EffectDescriptor { get }

    /// Produces sprites in local time, starting at 0.
    ///
    /// The returned commands must stay within `0...context.duration`; the
    /// evaluator shifts them into place and is the only thing that knows where
    /// the node sits.
    func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite]
}
