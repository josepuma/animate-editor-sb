import Foundation

/// What an effect is, and what it can be asked for.
///
/// Native effects declare one of these in Swift; a script will declare the same
/// shape as JSON. Nothing downstream — the inspector above all — is told which
/// of the two it is looking at.
public struct EffectDescriptor: Sendable, Equatable {
    public static func == (lhs: EffectDescriptor, rhs: EffectDescriptor) -> Bool {
        // Compared by what it declares. `initialTransform` is a closure and has
        // no equality of its own, and two descriptors of the same type are the
        // same effect however it was built.
        lhs.type == rhs.type
            && lhs.name == rhs.name
            && lhs.category == rhs.category
            && lhs.systemImage == rhs.systemImage
            && lhs.parameters == rhs.parameters
    }

    /// Stable identifier used to match a node back to its effect, so a saved
    /// document survives a renamed display title.
    public let type: String
    public var name: String
    /// Grouping for the effect browser.
    public var category: String
    /// SF Symbol shown beside the name.
    public var systemImage: String
    public var parameters: [EffectParameter]

    public init(
        type: String,
        name: String,
        category: String,
        systemImage: String,
        parameters: [EffectParameter],
    ) {
        self.type = type
        self.name = name
        self.category = category
        self.systemImage = systemImage
        self.parameters = parameters
    }

    /// A descriptor whose nodes start with something animated.
    public init(
        type: String,
        name: String,
        category: String,
        systemImage: String,
        parameters: [EffectParameter],
        initialTransform: @escaping @Sendable (Double) -> Transform,
    ) {
        self.init(
            type: type,
            name: name,
            category: category,
            systemImage: systemImage,
            parameters: parameters,
        )
        self.initialTransform = initialTransform
    }

    public func parameter(_ id: String) -> EffectParameter? {
        parameters.first { $0.id == id }
    }

    /// Parameter group headings, in declaration order and without repeats.
    ///
    /// Order comes from the parameter list rather than a separate list of
    /// groups: two lists drift, and the one that drifts is always the one
    /// nobody updates when a parameter is added.
    public var groups: [String] {
        var seen: Set<String> = []
        return parameters.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    /// What a freshly placed node of this effect animates.
    ///
    /// Declared on the descriptor so every route that places one — the library,
    /// a preset, a dropped asset — arrives at the same starting state. An
    /// effect that wants nothing animated returns an empty transform, which is
    /// the default.
    public var initialTransform: @Sendable (Double) -> Transform = { _ in Transform() }

    /// Every parameter at its default, ready for a newly created node.
    public var defaultValues: [String: EffectValue] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.defaultValue) })
    }
}

/// One placed instance of an effect: which effect, when it runs, and how it is
/// configured.
///
/// This — not the sprites it produces — is what the document stores. Keeping
/// the intent means a placed effect stays editable; keeping its output would
/// leave thousands of loose commands with no way back to the emitter that
/// wrote them.
public struct EffectNode: Identifiable, Sendable, Equatable, Codable {
    // ─── Decoding ────────────────────────────────────────────────────────────

    private enum CodingKeys: String, CodingKey {
        case id, type, name, layer, startTime, duration, seed, values
        case transform, filters, layers, isVisible, isLocked
    }

    /// Written before filters moved onto the clip, a node has none of its own.
    ///
    /// Absent keys are read as their empty value rather than as a failure: a
    /// project saved by an older build is a project someone still has, and a
    /// decoder that refuses it opens their work as a blank document.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        layer = try container.decode(Layer.self, forKey: .layer)
        startTime = try container.decode(Double.self, forKey: .startTime)
        duration = try container.decode(Double.self, forKey: .duration)
        seed = try container.decode(UInt64.self, forKey: .seed)
        values = try container.decode([String: EffectValue].self, forKey: .values)
        transform = try container.decodeIfPresent(Transform.self, forKey: .transform) ?? Transform()
        filters = try container.decodeIfPresent([FilterNode].self, forKey: .filters) ?? []
        // Absent in every project written before compound effects existed, and
        // an effect with no layers is the ordinary single-layer kind.
        layers = try container.decodeIfPresent([EffectNode].self, forKey: .layers) ?? []
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    public let id: String
    /// Matches `EffectDescriptor.type`.
    public let type: String
    public var name: String
    public var layer: Layer
    /// Where the effect sits on the timeline. Evaluation happens in local time
    /// and is offset by `startTime`, so dragging the block moves the same
    /// particles instead of drawing new ones.
    public var startTime: Double
    public var duration: Double
    /// Fixes the random stream, so the same node always evaluates to the same
    /// sprites — a preview that disagrees with the export is otherwise only
    /// noticed once a file is out the door.
    public var seed: UInt64
    public var values: [String: EffectValue]
    /// Keyframed position, scale, rotation and opacity.
    ///
    /// Separate from `values` because it is a different shape: a parameter is
    /// one number, and a transform property is a number over time. Keeping the
    /// two apart means the inspector can render parameters generically while
    /// the timeline lays keyframes out, without either pretending to be the
    /// other.
    public var transform: Transform
    /// Filters applied to this clip's output, in order.
    ///
    /// On the clip rather than on its lane. A filter is dragged onto the thing
    /// it will change, and a drop that lands on a clip while quietly applying
    /// to everything around it promises one thing and does another. Ordered
    /// because they compose — a glow after an echo lights the trail, and before
    /// it the trail carries copies of the glow.
    public var filters: [FilterNode]
    /// Further effects drawn as part of this one.
    ///
    /// What makes a compound effect: a circle of fire is a base, embers and a
    /// halo, each with its own sprite and its own numbers, arranged as one
    /// thing. They move together on the timeline, share a bounding box on the
    /// canvas, and are edited separately in the inspector.
    ///
    /// Layers rather than a separate `CompoundEffect` type: a layer is an
    /// `EffectNode` like any other, so it already has parameters, a transform,
    /// keyframes and filters — none of which had to be invented again. The
    /// parent's transform carries the lot.
    ///
    /// One level deep. A layer holding layers is a tree, and a tree needs an
    /// outliner to edit; two levels covers every compound effect anyone has
    /// asked for.
    public var layers: [EffectNode]

    public var isVisible: Bool
    public var isLocked: Bool

    public init(
        id: String,
        type: String,
        name: String,
        layer: Layer = .foreground,
        startTime: Double,
        duration: Double,
        seed: UInt64 = 1,
        values: [String: EffectValue] = [:],
        transform: Transform = Transform(),
        filters: [FilterNode] = [],
        layers: [EffectNode] = [],
        isVisible: Bool = true,
        isLocked: Bool = false,
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.layer = layer
        self.startTime = startTime
        self.duration = duration
        self.seed = seed
        self.values = values
        self.transform = transform
        self.filters = filters
        self.layers = layers
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    public var endTime: Double { startTime + duration }

    /// How many times a loop filter repeats this clip, or 1 if none does.
    ///
    /// A loop is the one filter that changes **how long a clip lasts**: it
    /// wraps the body in osu!'s own `_L`, so a four-second clip looped five
    /// times occupies twenty seconds of the map. Every other filter reshapes
    /// what a clip draws without touching its span.
    public var loopRepeats: Int {
        // Only an enabled loop counts, so switching one off shortens the block
        // back the way switching it on lengthened it.
        let counts = filters
            .filter { $0.isEnabled && $0.type == "loop" }
            .compactMap { filter -> Int? in
                guard case let .integer(count) = filter.values["count"] else { return nil }
                return max(1, count)
            }

        // Two loops on one clip multiply, the way nesting would.
        return counts.reduce(1, *)
    }

    /// Where the clip actually stops playing, loops included.
    ///
    /// Distinct from `endTime`, which is where the *clip* ends — the thing a
    /// drag resizes and keyframes are measured against. The timeline needs
    /// both: one to edit, one to draw. Showing `endTime` for a looped clip has
    /// the block finish while the effect is still going, which is a timeline
    /// lying about the only thing it exists to show.
    public var playbackEndTime: Double {
        startTime + duration * Double(loopRepeats)
    }
    public var timeRange: ClosedRange<Double> { startTime...max(startTime, endTime) }
}


public extension EffectNode {
    /// This node's layers, re-homed under a new parent id.
    ///
    /// A layer's id prefixes every sprite it makes, so two nodes sharing one
    /// would name the same sprites and collapse into each other. Their seeds
    /// move too, or a copy is the same particle field drawn twice.
    ///
    /// Shared rather than written at each call site: copy and duplicate both
    /// need it, and this project has already watched `filters` get dropped from
    /// one path and then the other.
    /// A layer's seed, derived from its parent's.
    ///
    /// Mixed, not offset. Stepping the seed by a constant is how the parent's
    /// own duplicate seed is made, so a layer that stepped by the same constant
    /// would land on a seed some other node already owns — a copy's first layer
    /// inherited the original's second layer, particle for particle. Mixing
    /// scatters them instead, which is the same reason `EffectRandom` mixes an
    /// index rather than adding it.
    static func layerSeed(from parent: UInt64, index: Int) -> UInt64 {
        var mixed = parent &+ (UInt64(index &+ 1) &* 0xA0761D6478BD642F)
        mixed = (mixed ^ (mixed >> 33)) &* 0xFF51AFD7ED558CCD
        mixed = (mixed ^ (mixed >> 29)) &* 0xC4CEB9FE1A85EC53
        return mixed ^ (mixed >> 32)
    }

    func layersRehomed(under parentID: EffectNode.ID, seed: UInt64) -> [EffectNode] {
        layers.enumerated().map { index, layer in
            EffectNode(
                id: "\(parentID)/L\(index)",
                type: layer.type,
                name: layer.name,
                layer: layer.layer,
                startTime: layer.startTime,
                duration: layer.duration,
                seed: EffectNode.layerSeed(from: seed, index: index),
                values: layer.values,
                transform: layer.transform,
                filters: layer.filters.map { $0.reidentified() },
                isVisible: layer.isVisible,
                isLocked: layer.isLocked,
            )
        }
    }
}
