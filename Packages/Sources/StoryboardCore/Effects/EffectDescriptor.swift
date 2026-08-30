import Foundation

/// What an effect is, and what it can be asked for.
///
/// Native effects declare one of these in Swift; a script will declare the same
/// shape as JSON. Nothing downstream — the inspector above all — is told which
/// of the two it is looking at.
public struct EffectDescriptor: Sendable, Equatable {
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
public struct EffectNode: Identifiable, Sendable, Equatable {
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
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    public var endTime: Double { startTime + duration }
    public var timeRange: ClosedRange<Double> { startTime...max(startTime, endTime) }
}
