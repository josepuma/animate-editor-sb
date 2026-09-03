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
            // By the declared order, not alphabetically: the categories are
            // listed roughly in the order they are reached for — something has
            // to exist before it can be styled.
            .sorted { LibraryCategory.precedes(($0.category, $0.name), ($1.category, $1.name)) }
    }

    /// The built-in library.
    public static let standard = EffectLibrary(effects: [ImageEffect(), ShapeEffect(), TextEffect(), EmitterEffect(), AudioBarsEffect()])
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

    /// The song's beat, for the effects that listen to it.
    ///
    /// Held by the evaluator rather than by each node: tempo belongs to the
    /// map, not to a clip placed on it, and storing a copy per effect would let
    /// them disagree with the song and with each other.
    public var beat: BeatGrid?

    public init(
        library: EffectLibrary = .standard,
        filters: FilterLibrary = .standard,
        beat: BeatGrid? = nil,
    ) {
        self.library = library
        self.filters = filters
        self.beat = beat
    }

    /// Evaluates one node into sprites positioned on the project timeline.
    public func evaluate(_ node: EffectNode) -> [StoryboardSprite] {
        guard node.isVisible else { return [] }
        guard let effect = library.effect(for: node.type) else { return [] }

        let descriptor = Swift.type(of: effect).descriptor
        let context = EffectContext(descriptor: descriptor, node: node, beat: beat)
        var rng = EffectRandom(seed: node.seed)

        var produced = effect.evaluate(in: context, rng: &rng)

        // Layers, drawn as part of this effect.
        //
        // Evaluated whole — each carries its own parameters, transform and
        // filters, so a layer is worked out exactly as a clip is — and appended
        // in order, which is the order they draw in. The parent's transform
        // below then carries the lot as one, which is what makes a compound
        // effect move as a single thing.
        for layer in node.layers where layer.isVisible {
            var nested = layer
            // Timed against the parent, not the project: a layer sits inside
            // its clip, and the clip's own offset is applied once at the end.
            nested.startTime = 0
            produced += evaluate(nested)
        }

        // The clip's transform first, then its filters.
        //
        // The transform is part of what the clip *is* — where it sits, how it
        // turns — while a filter reshapes the finished thing. Run the other way
        // round, a loop packed the clip's commands into a loop body and the
        // transform then wrote its movement *outside* that body: the motion
        // played once and the sprite sat frozen at its last value for every
        // remaining pass.
        var placed = GroupTransform.apply(
            node.transform,
            to: produced,
            duration: node.duration,
        )

        for filterNode in node.filters where filterNode.isEnabled {
            guard let filter = filters.filter(for: filterNode.type) else { continue }
            let descriptor = Swift.type(of: filter).descriptor
            placed = filter.apply(
                to: placed,
                in: FilterContext(
                    descriptor: descriptor,
                    node: filterNode,
                    beat: beat,
                    transform: node.transform,
                ),
            )
        }

        return placed.map { shift($0, by: node.startTime, layer: node.layer) }
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

        // The lane owns the layer, so everything on it takes that layer.
        return evaluate(track.nodes).map { sprite in
            var placed = sprite
            placed.layer = track.layer
            return placed
        }
    }

    /// How much longer a track's filters make its clips run.
    ///
    /// A loop repeats what is on the lane, so the block drawn on the timeline
    /// is no longer the whole of it.
    public func duration(of clipDuration: Double, on node: EffectNode) -> Double {
        node.filters
            .filter(\.isEnabled)
            .reduce(clipDuration) { running, filterNode in
                guard let filter = filters.filter(for: filterNode.type) else { return running }
                let descriptor = Swift.type(of: filter).descriptor
                return filter.duration(
                    of: running,
                    in: FilterContext(descriptor: descriptor, node: filterNode, beat: beat),
                )
            }
    }

    /// How many sprites a track's filters would multiply its output by.
    ///
    /// Reported so the editor can warn before a `.osb` is written: a glow over
    /// a large emitter is a file osu! will not open, and that is worth knowing
    /// while it can still be turned down.
    public func spriteMultiplier(for node: EffectNode) -> Double {
        node.filters
            .filter(\.isEnabled)
            .reduce(1.0) { total, filterNode in
                guard let filter = filters.filter(for: filterNode.type) else { return total }
                let descriptor = Swift.type(of: filter).descriptor
                return total * filter.estimatedMultiplier(
                    in: FilterContext(descriptor: descriptor, node: filterNode, beat: beat),
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
