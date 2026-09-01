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
    public var category: String
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
        )
    }
    /// Matches `FilterDescriptor.type`.
    public let type: String
    public var isEnabled: Bool
    public var values: [String: EffectValue]

    public init(
        id: String,
        type: String,
        isEnabled: Bool = true,
        values: [String: EffectValue] = [:],
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.values = values
    }
}

/// Everything a filter is handed when it runs.
public struct FilterContext: Sendable {
    public let descriptor: FilterDescriptor
    public let node: FilterNode
    /// Prefix for sprites the filter adds, so two filters on one track cannot
    /// produce colliding ids.
    public let idPrefix: String

    private let values: [String: EffectValue]

    public init(descriptor: FilterDescriptor, node: FilterNode) {
        self.descriptor = descriptor
        self.node = node
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
    }

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
            .sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    /// The built-in library.
    public static let standard = FilterLibrary(filters: [
        GlowFilter(), ShadowFilter(), BlurFilter(), TintFilter(),
        EchoFilter(), WiggleFilter(), LoopFilter(),
        TimeFilter(), EaseFilter(), RadialFilter(),
        MirrorFilter(), ChromaticFilter(), PathFilter(),
    ])
}
