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
    public let filters: FilterLibrary

    public init(library: EffectLibrary = .standard, filters: FilterLibrary = .standard) {
        self.library = library
        self.filters = filters
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

    /// Evaluates a whole document, track by track.
    ///
    /// Track order is draw order within a layer, and a hidden track contributes
    /// nothing regardless of what its effects say — hiding a lane has to hide
    /// what is on it, which is the only reading of the control that makes sense.
    public func evaluate(_ document: EffectDocument) -> [StoryboardSprite] {
        document.tracks.flatMap { evaluate($0) }
    }

    /// Evaluates one track: its effects, then its filters over the result.
    ///
    /// Filters run here rather than at export, which is the whole point. A
    /// filter that only ran on the way out would be invisible in the editor —
    /// and two paths to the same picture drift, so the one that ships would be
    /// the one nobody had looked at. Everything a filter does is sprites, so
    /// there is no reason to have two.
    public func evaluate(_ track: EffectTrack) -> [StoryboardSprite] {
        guard track.isVisible else { return [] }

        var sprites = evaluate(track.nodes)

        for node in track.filters where node.isEnabled {
            guard let filter = filters.filter(for: node.type) else { continue }
            let descriptor = Swift.type(of: filter).descriptor
            let context = FilterContext(descriptor: descriptor, node: node)
            sprites = filter.apply(to: sprites, in: context)
        }

        // The lane owns the layer, so anything a filter added takes it too.
        return sprites.map { sprite in
            var placed = sprite
            placed.layer = track.layer
            return placed
        }
    }

    /// How many sprites a track's filters would multiply its output by.
    ///
    /// Reported so the editor can warn before a `.osb` is written: a glow over
    /// a large emitter is a file osu! will not open, and that is worth knowing
    /// while it can still be turned down.
    public func spriteMultiplier(for track: EffectTrack) -> Double {
        track.filters
            .filter(\.isEnabled)
            .reduce(1.0) { total, node in
                guard let filter = filters.filter(for: node.type) else { return total }
                let descriptor = Swift.type(of: filter).descriptor
                return total * filter.estimatedMultiplier(
                    in: FilterContext(descriptor: descriptor, node: node),
                )
            }
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
