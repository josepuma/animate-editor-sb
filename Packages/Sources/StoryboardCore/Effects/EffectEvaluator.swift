import Foundation

/// The effects available to place, looked up by `EffectDescriptor.type`.
///
/// Native effects register here; scripted ones will register the same way once
/// there is a runtime to evaluate them. Everything downstream asks the registry
/// rather than switching on a known list.
public struct EffectLibrary: Sendable {
    private var effects: [String: any Effect]

    public init(effects: [any Effect] = []) {
        self.effects = Dictionary(
            uniqueKeysWithValues: effects.map { (type(of: $0).descriptor.type, $0) },
        )
    }

    public mutating func register(_ effect: any Effect) {
        effects[type(of: effect).descriptor.type] = effect
    }

    public func effect(for type: String) -> (any Effect)? {
        effects[type]
    }

    public func descriptor(for type: String) -> EffectDescriptor? {
        effects[type].map { Swift.type(of: $0).descriptor }
    }

    /// Everything registered, ordered for the effect browser.
    public var descriptors: [EffectDescriptor] {
        effects.values
            .map { Swift.type(of: $0).descriptor }
            .sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    /// The built-in library.
    public static let standard = EffectLibrary(effects: [EmitterEffect()])
}

/// Turns placed effect nodes into the sprites the renderer and the exporter
/// already understand.
///
/// The offset lives here and nowhere else. An effect generates from 0 and is
/// shifted into place afterwards, which is what makes dragging a block on the
/// timeline move its output rather than regenerate it — the same rule After
/// Effects follows, and the reason a layer can be nudged without the art
/// changing underneath.
public struct EffectEvaluator: Sendable {
    public let library: EffectLibrary

    public init(library: EffectLibrary = .standard) {
        self.library = library
    }

    /// Evaluates one node into sprites positioned on the project timeline.
    public func evaluate(_ node: EffectNode) -> [StoryboardSprite] {
        guard node.isVisible else { return [] }
        guard let effect = library.effect(for: node.type) else { return [] }

        let descriptor = Swift.type(of: effect).descriptor
        let context = EffectContext(descriptor: descriptor, node: node)
        var rng = EffectRandom(seed: node.seed)

        return effect.evaluate(in: context, rng: &rng).map {
            shift($0, by: node.startTime, layer: node.layer)
        }
    }

    /// Evaluates every node, in the order given.
    public func evaluate(_ nodes: [EffectNode]) -> [StoryboardSprite] {
        nodes.flatMap { evaluate($0) }
    }

    /// Moves a locally-timed sprite onto the project timeline.
    private func shift(
        _ sprite: StoryboardSprite,
        by offset: Double,
        layer: Layer,
    ) -> StoryboardSprite {
        var shifted = sprite
        shifted.layer = layer
        shifted.commands = sprite.commands.map { command in
            var moved = command
            moved.timing.startTime += offset
            moved.timing.endTime += offset
            return moved
        }
        // A loop's body is relative to the loop's own start, so only the start
        // moves — shifting the body as well would push each iteration out by
        // the offset twice.
        shifted.loops = sprite.loops.map { loop in
            var moved = loop
            moved.startTime += offset
            return moved
        }
        return shifted
    }
}
