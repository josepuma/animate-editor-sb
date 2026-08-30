import Foundation
import StoryboardCore

/// Which panel the left rail is showing.
public enum SidePanel: String, CaseIterable, Identifiable, Sendable {
    case assets
    case scripts
    case filters
    case layers
    case timing

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .assets: "photo.stack"
        case .scripts: "curlybraces"
        case .filters: "wand.and.stars"
        case .layers: "square.3.layers.3d"
        case .timing: "metronome"
        }
    }

    public var title: String {
        switch self {
        case .assets: "Assets"
        case .scripts: "Effects"
        case .filters: "Filters"
        case .layers: "Layers"
        case .timing: "Timing"
        }
    }
}

/// An image the storyboard references.
public struct AssetItem: Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all
        case image
        case audio

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .all: "All"
            case .image: "Images"
            case .audio: "Audio"
            }
        }
    }

    public let id: String
    public var name: String
    public var path: String
    public var kind: Kind
    /// How many sprites reference this file.
    public var useCount: Int
    public var isMissing: Bool

    public init(
        id: String,
        name: String,
        path: String,
        kind: Kind,
        useCount: Int,
        isMissing: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.useCount = useCount
        self.isMissing = isMissing
    }
}

/// State for the editor shell: which panels are open and what they show.
@MainActor
@Observable
public final class EditorShellModel {
    public var sidePanel: SidePanel = .layers
    public var isSidePanelVisible = true
    public var isInspectorVisible = true
    public var assetFilter: AssetItem.Kind = .all

    public private(set) var assets: [AssetItem] = []

    /// The lane the next effect lands on, and what the inspector shows when no
    /// effect is selected.
    public var selectedTrackID: EffectTrack.ID?
    /// The effect being edited.
    public var selectedNodeID: EffectNode.ID?

    /// The last evaluation, kept so the sprites are produced once per change
    /// rather than once per reader.
    private var evaluated: [StoryboardSprite] = []

    /// Where a clip being dragged would land, while the drag is in flight.
    ///
    /// Held here rather than in the row doing the dragging because the preview
    /// belongs to a *different* row — the destination — and a row cannot draw
    /// into its neighbour.
    public struct DropPreview: Equatable, Sendable {
        public let nodeID: EffectNode.ID
        public let trackID: EffectTrack.ID
        public let range: ClosedRange<Double>
    }

    public var dropPreview: DropPreview?

    public var visibleAssets: [AssetItem] {
        assetFilter == .all ? assets : assets.filter { $0.kind == assetFilter }
    }

    /// The effects placed on the timeline — what the project actually authors,
    /// as opposed to the layer tracks derived from a parsed `.osb`.
    public private(set) var effects = EffectDocument()
    public let library: EffectLibrary
    public let filters: FilterLibrary
    private let evaluator: EffectEvaluator

    /// Bumped whenever an effect changes, so views that re-evaluate can watch
    /// one value instead of diffing the whole document.
    public private(set) var effectsRevision = 0

    public init(library: EffectLibrary = .standard, filters: FilterLibrary = .standard) {
        self.library = library
        self.filters = filters
        evaluator = EffectEvaluator(library: library, filters: filters)
    }

    // ─── Effects ─────────────────────────────────────────────────────────────

    /// The effect the inspector edits.
    ///
    /// Falls back to the only effect on the selected lane. Clicking a row with
    /// one clip on it and getting an empty inspector is the wrong answer to an
    /// obvious question — there is exactly one thing there to edit. With
    /// several, the lane itself is the selection and the inspector shows what a
    /// lane has.
    public var selectedEffect: EffectNode? {
        if let selectedNodeID, let node = effects[selectedNodeID] { return node }
        guard let track = selectedTrack, track.nodes.count == 1 else { return nil }
        return track.nodes[0]
    }

    /// The descriptor behind the selected effect, for the inspector to render.
    public var selectedDescriptor: EffectDescriptor? {
        guard let node = selectedEffect else { return nil }
        return library.descriptor(for: node.type)
    }

    /// The track the selection belongs to, or the selected track itself.
    public var selectedTrack: EffectTrack? {
        if let selectedNodeID, let id = effects.trackID(of: selectedNodeID) {
            return effects.track(id: id)
        }
        guard let selectedTrackID else { return nil }
        return effects.track(id: selectedTrackID)
    }

    /// Every placed effect evaluated into sprites.
    public func evaluateEffects() -> [StoryboardSprite] {
        evaluated
    }

    /// Presets available for the effects in the library.
    public var presets: [EffectPreset] {
        EmitterEffect.presets.filter { library.descriptor(for: $0.effectType) != nil }
    }

    // ─── Placing ─────────────────────────────────────────────────────────────

    /// Where a new effect lands: the selected track, or a new one.
    private var destinationTrackID: EffectTrack.ID? {
        selectedTrack?.id ?? effects.tracks.last?.id
    }

    @discardableResult
    public func addEffect(
        _ descriptor: EffectDescriptor,
        at startTime: Double,
        duration: Double = 2000,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode {
        let node = effects.add(
            descriptor,
            at: startTime,
            duration: duration,
            on: trackID ?? destinationTrackID,
        )
        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Places a preset, using the length the preset asks for.
    ///
    /// The duration is the preset's rather than a fixed default because a burst
    /// and a stream want very different blocks: a shockwave lasts under a
    /// second, and stretching it over five leaves four of nothing.
    @discardableResult
    public func addPreset(
        _ preset: EffectPreset,
        at startTime: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let descriptor = library.descriptor(for: preset.effectType) else { return nil }

        var node = effects.add(
            descriptor,
            at: startTime,
            duration: preset.duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = preset.name
        node.values = preset.values
        effects[node.id] = node

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    // ─── Editing effects ─────────────────────────────────────────────────────

    public func removeEffect(_ nodeID: EffectNode.ID) {
        effects.remove(nodeID)
        if selectedNodeID == nodeID { selectedNodeID = nil }
        effectsChanged()
    }

    public func setValue(_ value: EffectValue, for parameterID: String, on nodeID: EffectNode.ID) {
        effects.setValue(value, for: parameterID, on: nodeID)
        effectsChanged()
    }

    public func moveEffect(_ nodeID: EffectNode.ID, to startTime: Double) {
        effects.move(nodeID, to: startTime)
        effectsChanged()
    }

    public func moveEffect(_ nodeID: EffectNode.ID, toTrack trackID: EffectTrack.ID) {
        effects.move(nodeID, toTrack: trackID)
        effectsChanged()
    }

    public func resizeEffect(_ nodeID: EffectNode.ID, startTime: Double, duration: Double) {
        effects.resize(nodeID, startTime: startTime, duration: duration)
        effectsChanged()
    }

    // ─── Editing tracks ──────────────────────────────────────────────────────

    @discardableResult
    public func addTrack() -> EffectTrack {
        let track = effects.addTrack()
        selectedTrackID = track.id
        selectedNodeID = nil
        effectsChanged()
        return track
    }

    public func removeTrack(_ trackID: EffectTrack.ID) {
        effects.removeTrack(trackID)
        if selectedTrackID == trackID { selectedTrackID = effects.tracks.last?.id }
        // The selected effect may have gone with the lane it was on.
        if let selectedNodeID, effects[selectedNodeID] == nil { self.selectedNodeID = nil }
        effectsChanged()
    }

    public func renameTrack(_ trackID: EffectTrack.ID, to name: String) {
        effects.rename(trackID, to: name)
        effectsChanged()
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// The filters available to apply.
    public var filterDescriptors: [FilterDescriptor] {
        filters.descriptors
    }

    @discardableResult
    public func addFilter(_ descriptor: FilterDescriptor, to trackID: EffectTrack.ID) -> FilterNode? {
        let node = effects.addFilter(descriptor, to: trackID)
        effectsChanged()
        return node
    }

    public func removeFilter(_ filterID: FilterNode.ID, from trackID: EffectTrack.ID) {
        effects.removeFilter(filterID, from: trackID)
        effectsChanged()
    }

    public func toggleFilter(_ filterID: FilterNode.ID, in trackID: EffectTrack.ID) {
        effects.toggleFilter(filterID, in: trackID)
        effectsChanged()
    }

    public func setFilterValue(
        _ value: EffectValue,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in trackID: EffectTrack.ID,
    ) {
        effects.setFilterValue(value, for: parameterID, on: filterID, in: trackID)
        effectsChanged()
    }

    /// How much a track's filters multiply its sprite count.
    ///
    /// Surfaced so a glow over a large emitter can be seen for what it is —
    /// a file osu! will not open — while it can still be turned down.
    public func spriteMultiplier(for trackID: EffectTrack.ID) -> Double {
        guard let track = effects.track(id: trackID) else { return 1 }
        return evaluator.spriteMultiplier(for: track)
    }

    public func setLayer(_ layer: Layer, on trackID: EffectTrack.ID) {
        effects.setLayer(layer, on: trackID)
        effectsChanged()
    }

    public func toggleVisibility(of trackID: EffectTrack.ID) {
        effects.toggleVisibility(of: trackID)
        effectsChanged()
    }

    public func toggleLock(of trackID: EffectTrack.ID) {
        effects.toggleLock(of: trackID)
        effectsChanged()
    }

    public func raiseTrack(_ trackID: EffectTrack.ID) {
        effects.raiseTrack(trackID)
        effectsChanged()
    }

    public func lowerTrack(_ trackID: EffectTrack.ID) {
        effects.lowerTrack(trackID)
        effectsChanged()
    }

    /// Signals that something about the effects changed and re-evaluates.
    private func effectsChanged() {
        effectsRevision &+= 1
        // One pass over the document: the sprites feed the canvas, and the
        // counts the UI shows come from the same evaluation. Counting
        // separately ran every emitter a second time for a number the first
        // pass already knew.
        evaluated = evaluator.evaluate(effects)
    }

    /// Sprite count of the storyboard the current tracks were built from.
    ///
    /// SwiftUI calls this from both `onAppear` and `onChange`, and rebuilding
    /// mutates observed state — which would feed straight back into another
    /// update. Rebuilding only when the content actually changed breaks that.
    private var loadedSpriteCount: Int?

    /// Reads the assets a parsed storyboard references.
    ///
    /// Tracks are no longer derived from the file: they are lanes the user
    /// authors. The assets panel still reads it, which is what that panel is
    /// for.
    public func load(sprites: [PreparedSprite], missingImagePaths: Set<String>) {
        guard loadedSpriteCount != sprites.count else { return }
        loadedSpriteCount = sprites.count

        var counts: [String: Int] = [:]
        for sprite in sprites {
            counts[sprite.filePath, default: 0] += 1
        }

        assets = counts
            .map { path, count in
                AssetItem(
                    id: path,
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    kind: .image,
                    useCount: count,
                    isMissing: missingImagePaths.contains(path),
                )
            }
            .sorted { $0.useCount > $1.useCount }
    }



}

// ─── Range merging ───────────────────────────────────────────────────────────

/// Collapses sprite lifetimes into the spans a track draws.
///
/// Kept separate from the model so it stays a pure function: it is the only
/// non-obvious logic here, and it is worth testing without a main actor.
enum TrackRanges {
    /// A track showing thousands of individual bars is unreadable and slow, so
    /// spans closer together than this are merged. Half a second reads as one
    /// continuous run at any zoom a whole-track view uses.
    static let gapThreshold: Double = 500

    static func merged(of sprites: [PreparedSprite]) -> [ClosedRange<Double>] {
        let sorted = sprites
            .map { $0.activeStart...Swift.max($0.activeStart, $0.activeEnd) }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }

        var merged: [ClosedRange<Double>] = []

        for range in sorted.dropFirst() {
            if range.lowerBound <= current.upperBound + gapThreshold {
                current = current.lowerBound...Swift.max(current.upperBound, range.upperBound)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }
}
