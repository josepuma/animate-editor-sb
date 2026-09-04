import Foundation

/// An effect that reshapes sprites rather than producing them.
///
/// Two kinds of thing live in this system. An ``Effect`` *generates* — an
/// emitter makes particles out of nothing. A filter *transforms* — a glow takes
/// whatever is on a track and gives back that plus a halo. After Effects draws
/// the same line between a generator and a layer effect, and for the same
/// reason: they answer different questions and compose differently.
///
/// ## What a filter can be
///
/// osu! has no shaders, so a filter cannot run a pass over the frame the way a
/// compositor would. It has two other moves, and between them they cover more
/// than the limitation suggests:
///
/// - **Add sprites.** A glow is a second copy behind the first; an echo is the
///   same sprite drawn where it used to be. This is what multiplies file size.
/// - **Change the image a sprite draws.** A blurred copy of a texture is still
///   one sprite, so softness costs pixels rather than sprites. See
///   ``DerivedSprite``.
///
/// What genuinely cannot be done is anything that reads the frame: a blur that
/// smears *overlapping* sprites together, refraction, colour grading against a
/// backdrop. Those are absent rather than faked badly.
///
/// Where a filter does add sprites the cost is real and multiplies, so
/// `estimatedMultiplier` exists to say so before the file is written.
public protocol SpriteFilter: Sendable {
    static var descriptor: FilterDescriptor { get }

    /// Reshapes a track's sprites.
    ///
    /// Receives everything the track produced, in draw order, and returns what
    /// should be drawn in its place — normally the input plus additions. The
    /// input is included rather than implied so a filter can drop or replace,
    /// not only decorate.
    func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite]

    /// How long a clip runs once this filter has had it.
    ///
    /// A loop repeats its clip, so what the timeline draws is no longer how
    /// long the effect lasts — and a block that says twenty-five seconds while
    /// playing for two minutes is a block nobody can arrange against.
    ///
    /// A duration rather than a multiplier: a loop with a gap between passes
    /// runs for its repeats *plus* that silence, and no single factor says
    /// that.
    func duration(of clipDuration: Double, in context: FilterContext) -> Double

    /// Roughly how many sprites come out for each one that goes in.
    ///
    /// Used to warn before an export rather than to allocate: a storyboard that
    /// osu! will not open is worth knowing about in the editor, and the number
    /// is knowable without running the filter.
    func estimatedMultiplier(in context: FilterContext) -> Double
}

public extension SpriteFilter {
    func estimatedMultiplier(in context: FilterContext) -> Double { 1 }
    /// Most filters change how a clip looks, not how long it runs.
    func duration(of clipDuration: Double, in context: FilterContext) -> Double { clipDuration }
}

/// What a filter is, and what it can be asked for.
///
/// Deliberately the same shape as ``EffectDescriptor``: the inspector renders
/// parameters without caring which of the two it is looking at, and a filter
/// written in a script will declare itself the same way a native one does.
public struct FilterDescriptor: Sendable, Equatable {
    public let type: String
    public var name: String
    public var category: LibraryCategory
    public var systemImage: String
    public var parameters: [EffectParameter]

    public init(
        type: String,
        name: String,
        category: LibraryCategory,
        systemImage: String,
        parameters: [EffectParameter],
    ) {
        self.type = type
        self.name = name
        self.category = category
        self.systemImage = systemImage
        self.parameters = parameters
    }

    public func parameter(_ id: String) -> EffectParameter? {
        parameters.first { $0.id == id }
    }

    public var groups: [String] {
        var seen: Set<String> = []
        return parameters.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    public var defaultValues: [String: EffectValue] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.defaultValue) })
    }
}

/// One filter applied to a track, with its settings.
public struct FilterNode: Identifiable, Sendable, Equatable, Codable {
    public let id: String

    /// The same filter with a fresh identity.
    ///
    /// A copy needs one: the id prefixes the sprites a filter derives, so two
    /// nodes sharing it would name the same sprites — and a wiggle seeded from
    /// it would wobble identically in both, which is a copy of a copy rather
    /// than a second effect.
    public func reidentified() -> FilterNode {
        FilterNode(
            id: "\(type)-\(UUID().uuidString.prefix(8))",
            type: type,
            isEnabled: isEnabled,
            values: values,
            animations: animations,
        )
    }
    /// Matches `FilterDescriptor.type`.
    public let type: String
    public var isEnabled: Bool
    public var values: [String: EffectValue]

    /// Keyframes for parameters being animated, by parameter id.
    ///
    /// Separate from `values` rather than folded into it, which is the same
    /// split ``Transform`` already draws between a resting value and its
    /// animation — and for the same reason. Editing a field with animation off
    /// changes the value; with animation on it plants a key. Merged, moving the
    /// playhead and typing a number would plant keys nobody asked for, in
    /// parameters nobody was animating.
    ///
    /// A parameter with no entry here reads its `values` entry, so every filter
    /// saved before this existed loads and runs unchanged.
    public var animations: [String: KeyframeTrack]

    public init(
        id: String,
        type: String,
        isEnabled: Bool = true,
        values: [String: EffectValue] = [:],
        animations: [String: KeyframeTrack] = [:],
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.values = values
        self.animations = animations
    }

    /// The tracks that actually drive a value, ignoring switched-off and empty
    /// ones. A disabled track falls back to the resting value, exactly as if it
    /// had no keys.
    public var activeAnimations: [String: KeyframeTrack] {
        animations.filter(\.value.isActive)
    }

    public var isAnimated: Bool {
        animations.values.contains(where: \.isAnimated)
    }

    // A project saved before `animations` existed has no such key, and
    // synthesised decoding treats a missing non-optional as a failure — so the
    // whole file would refuse to open rather than open without animation. The
    // same trap `"scale"` fell into when it became two axes.
    private enum CodingKeys: String, CodingKey {
        case id, type, isEnabled, values, animations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        values = try container.decodeIfPresent([String: EffectValue].self, forKey: .values) ?? [:]
        animations = try container.decodeIfPresent(
            [String: KeyframeTrack].self, forKey: .animations,
        ) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(values, forKey: .values)
        // Omitted when empty, so adding this did not rewrite every saved
        // project's diff on the next save.
        if !animations.isEmpty { try container.encode(animations, forKey: .animations) }
    }
}

/// Everything a filter is handed when it runs.
public struct FilterContext: Sendable {
    public let descriptor: FilterDescriptor
    public let node: FilterNode
    /// Prefix for sprites the filter adds, so two filters on one track cannot
    /// produce colliding ids.
    public let idPrefix: String

    /// The song's beat, when there is one.
    ///
    /// A filter that listens to the music reads it from here rather than from
    /// its own parameters: tempo belongs to the map, so a copied clip beats
    /// with the song it was dropped on instead of the one it was written for.
    public let beat: BeatGrid?

    /// The clip's own transform, for a filter that needs to know how the group
    /// is being moved rather than how each sprite is.
    ///
    /// A filter runs after the transform, so by then a rotation exists only as
    /// `_R` commands — and those are indistinguishable from a sprite's *own*
    /// tilt. An emitter gives every particle a random one, so a filter reading
    /// the commands sees a clip spinning wildly when nothing is animated at
    /// all. The group's motion has to be handed over, not inferred.
    public let transform: Transform

    private let values: [String: EffectValue]

    public init(
        descriptor: FilterDescriptor,
        node: FilterNode,
        beat: BeatGrid? = nil,
        transform: Transform = Transform(),
    ) {
        self.descriptor = descriptor
        self.node = node
        self.beat = beat
        self.transform = transform
        idPrefix = node.id

        // Read through the declaration, so a node saved before a parameter
        // existed still runs: the missing entry falls back to its default.
        var resolved = descriptor.defaultValues
        for parameter in descriptor.parameters {
            if let stored = node.values[parameter.id] {
                resolved[parameter.id] = parameter.coerce(stored)
            }
        }
        values = resolved

        // Only tracks that drive something, clamped by what the parameter
        // accepts. A key dragged past a slider's range would otherwise write a
        // value the same parameter refuses when typed.
        var tracks: [String: KeyframeTrack] = [:]
        for parameter in descriptor.parameters {
            guard parameter.animation.isAnimatable else { continue }

            if parameter.kind == .color {
                // A colour animates as three channel tracks under derived keys,
                // which are not declared parameters — so they are clamped to
                // the channel range rather than to the parameter's own.
                let keys = Self.channelKeys(of: parameter.id)
                for key in [keys.r, keys.g, keys.b] {
                    guard let track = node.animations[key], track.isActive else { continue }
                    tracks[key] = track
                }
                continue
            }

            guard let track = node.animations[parameter.id], track.isActive else { continue }
            tracks[parameter.id] = parameter.clampingTrack(track)
        }
        animations = tracks
    }

    /// The keyframes in force, by parameter id. Empty for a filter nobody is
    /// animating, which is every filter until somebody clicks a stopwatch.
    public let animations: [String: KeyframeTrack]

    /// Whether `id` is being animated, so a filter can take the cheap path when
    /// it is not.
    ///
    /// Worth asking rather than always cutting segments: a filter that writes
    /// one command for a still value must keep writing one, or every project
    /// that never touched a stopwatch would start paying for keyframes it does
    /// not have.
    public func isAnimated(_ id: String) -> Bool {
        animations[id]?.isAnimated ?? false
    }

    /// Every moment any animated parameter names, so no key falls inside a
    /// segment another parameter defined.
    ///
    /// The same rule position and scale already follow: a key on one channel
    /// has to be a command boundary for all of them, or its curve is lost
    /// inside a span the other one drew.
    public func keyTimes(of ids: [String]) -> [Double] {
        var times: Set<Double> = []
        for id in ids {
            guard let track = animations[id], track.isAnimated else { continue }
            for key in track.keyframes { times.insert(key.time) }
        }
        return times.sorted()
    }

    public func number(_ id: String) -> Double {
        switch values[id] {
        case let .number(value): value
        case let .integer(value): Double(value)
        default: 0
        }
    }

    /// A numeric parameter at a moment in the clip.
    ///
    /// Falls back to the resting value when nothing is animating it, so a
    /// filter can ask with a time unconditionally and still behave exactly as
    /// it did before anyone added keys.
    public func number(_ id: String, at time: Double) -> Double {
        guard let track = animations[id], track.isActive else { return number(id) }
        return track.value(at: time)
    }

    /// The easing leaving the key at `time`, for a filter cutting its own
    /// commands at keyframe boundaries.
    ///
    /// A segment carries the curve of the key it *leaves from* — the same rule
    /// a storyboard command follows — so a filter writing one command per
    /// segment has to ask for it rather than defaulting to linear, which is the
    /// one curve nothing real follows.
    public func easing(of id: String, leaving time: Double) -> Easing {
        guard let track = animations[id] else { return .linear }
        return track.keyframes.last { $0.time <= time }?.easing ?? .linear
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

    /// The channel keys a colour parameter animates under.
    ///
    /// Three tracks rather than one, exactly as ``Transform`` splits colour into
    /// `red`, `green` and `blue`: a keyframe holds a `Double`, and the format
    /// already breaks a colour into three numbers when it writes `_C`. The
    /// alternative — a keyframe able to hold any type — would touch every piece
    /// of code that reads one, for the one parameter that needs it.
    ///
    /// Presented as a single colour well with a single stopwatch; the three
    /// move together.
    public static func channelKeys(of id: String) -> (r: String, g: String, b: String) {
        ("\(id).r", "\(id).g", "\(id).b")
    }

    /// A colour parameter at a moment, following its channel tracks when they
    /// are animated and its resting value when they are not.
    public func color(_ id: String, at time: Double) -> EffectColor {
        let resting = color(id)
        let keys = Self.channelKeys(of: id)
        guard animations[keys.r]?.isActive == true
            || animations[keys.g]?.isActive == true
            || animations[keys.b]?.isActive == true
        else { return resting }

        // A channel nobody animated holds the resting value, so animating one
        // of the three does not drag the other two to zero.
        func channel(_ key: String, _ fallback: Double) -> Double {
            guard let track = animations[key], track.isActive else { return fallback }
            return min(255, max(0, track.value(at: time)))
        }
        return EffectColor(
            r: channel(keys.r, resting.r),
            g: channel(keys.g, resting.g),
            b: channel(keys.b, resting.b),
        )
    }

    /// Whether a colour parameter is being animated on any channel.
    public func isColorAnimated(_ id: String) -> Bool {
        let keys = Self.channelKeys(of: id)
        return [keys.r, keys.g, keys.b].contains { animations[$0]?.isAnimated == true }
    }

    public func text(_ id: String) -> String {
        if case let .text(value) = values[id] { return value }
        return ""
    }

    public func path(_ id: String) -> MotionPath {
        if case let .path(value) = values[id] { return value }
        return MotionPath()
    }
}

/// The filters available to apply, looked up by type.
public struct FilterLibrary: Sendable {
    private var filters: [String: any SpriteFilter]

    public init(filters: [any SpriteFilter] = []) {
        self.filters = Dictionary(
            uniqueKeysWithValues: filters.map { (type(of: $0).descriptor.type, $0) },
        )
    }

    public mutating func register(_ filter: any SpriteFilter) {
        filters[type(of: filter).descriptor.type] = filter
    }

    public func filter(for type: String) -> (any SpriteFilter)? {
        filters[type]
    }

    public func descriptor(for type: String) -> FilterDescriptor? {
        filters[type].map { Swift.type(of: $0).descriptor }
    }

    public var descriptors: [FilterDescriptor] {
        filters.values
            .map { Swift.type(of: $0).descriptor }
            // By the declared order, not alphabetically: the categories are
            // listed roughly in the order they are reached for — something has
            // to exist before it can be styled.
            .sorted { LibraryCategory.precedes(($0.category, $0.name), ($1.category, $1.name)) }
    }

    /// The built-in library.
    public static let standard = FilterLibrary(filters: [
        GlowFilter(), ShadowFilter(), BlurFilter(), TintFilter(),
        EchoFilter(), WiggleFilter(), LoopFilter(),
        TimeFilter(), EaseFilter(), RadialFilter(),
        MirrorFilter(), ChromaticFilter(), PathFilter(), PulseFilter(), GridFilter(),
    ])
}
