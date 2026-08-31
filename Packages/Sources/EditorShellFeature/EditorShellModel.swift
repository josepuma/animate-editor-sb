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

    /// The keyframe being edited, if any.
    ///
    /// Selected rather than only draggable: a key's easing and its exact time
    /// are worth editing in a field, and a field needs to know which key it is
    /// talking about.
    public struct KeyframeSelection: Equatable, Sendable {
        public let nodeID: EffectNode.ID
        public let property: TransformProperty
        public let keyframeID: Keyframe.ID
    }

    public var selectedKeyframe: KeyframeSelection?

    /// The selected key itself, when there is one.
    public var selectedKeyframeValue: Keyframe? {
        guard let selection = selectedKeyframe,
              let node = effects[selection.nodeID]
        else { return nil }
        return node.transform[selection.property].keyframes
            .first { $0.id == selection.keyframeID }
    }

    /// The clip whose keyframes the timeline is showing, if any.
    ///
    /// A mode rather than rows stacked under every lane: five properties per
    /// clip is unreadable by the second clip, and the keys are worth the whole
    /// timeline's width when you are actually working on them. Double-clicking
    /// a clip is how a video editor opens something for detailed work.
    public var keyframeNodeID: EffectNode.ID? {
        didSet {
            // A selection belongs to the clip being edited: leaving that clip
            // would otherwise leave the inspector showing a key from a row that
            // is no longer on screen.
            if keyframeNodeID != oldValue { selectedKeyframe = nil }
        }
    }

    /// The clip the keyframe editor is open on.
    public var keyframeNode: EffectNode? {
        guard let keyframeNodeID else { return nil }
        return effects[keyframeNodeID]
    }

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

        // A preset's position moves onto the transform, which is where position
        // lives now. Left in `values` it would be read by nothing and the
        // emitter would sit at the canvas centre whatever the preset said.
        if case let .number(x) = preset.values[EmitterEffect.Param.x] {
            node.transform[value: .x] = x
        }
        if case let .number(y) = preset.values[EmitterEffect.Param.y] {
            node.transform[value: .y] = y
        }

        effects[node.id] = node

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Places an image on the timeline.
    ///
    /// Its own method rather than a preset because the path is the point: an
    /// image effect with no file draws nothing, so the one thing it must be
    /// given is the thing an asset row already knows.
    @discardableResult
    public func addImage(
        at path: String,
        time: Double,
        duration: Double = 4000,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let descriptor = library.descriptor(for: ImageEffect.descriptor.type) else {
            return nil
        }

        var node = effects.add(
            descriptor,
            at: time,
            duration: duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = (path as NSString).lastPathComponent
        node.values[ImageEffect.Param.sprite] = .text(path)
        effects[node.id] = node

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    // ─── Editing effects ─────────────────────────────────────────────────────

    // ─── Clipboard ───────────────────────────────────────────────────────────

    // ─── Saving ──────────────────────────────────────────────────────────────

    /// Where this project is saved, once it has a home.
    public var projectFolder: URL?

    /// Set when a project exists on disk but could not be read.
    ///
    /// Saving is refused while this is true. A file that failed to open is
    /// still someone's work, and writing an empty document over it turns a bug
    /// that could be fixed into a project that is gone.
    public private(set) var loadFailed = false

    /// Whether anything has changed since the last save.
    public private(set) var hasUnsavedChanges = false

    /// The last save's outcome, for the UI to show.
    public private(set) var saveError: String?

    /// Loads a project from a beatmap folder, if it has one.
    ///
    /// Silent when there is none: most folders have never been opened here, and
    /// that is the ordinary case rather than a failure.
    public func loadProject(fromFolder folder: URL) {
        projectFolder = folder
        loadFailed = false
        do {
            guard let project = try ProjectFile.read(fromFolder: folder) else { return }
            effects = project.document
            selectedNodeID = nil
            selectedTrackID = effects.tracks.last?.id
            effectsChanged()
            // Loading is not a change: a project opened and closed untouched
            // should not claim to need saving.
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            loadFailed = true
            saveError = "Could not open the project in this folder: \(error)"
        }
    }

    @discardableResult
    public func saveProject() -> Bool {
        guard let projectFolder, !loadFailed else { return false }
        do {
            try ProjectFile.write(Project(document: effects), toFolder: projectFolder)
            hasUnsavedChanges = false
            saveError = nil
            return true
        } catch {
            saveError = String(describing: error)
            return false
        }
    }

    // ─── Exporting ───────────────────────────────────────────────────────────

    /// Writes the storyboard out, if someone has wired up how.
    ///
    /// The shell does not export it itself: the images an export has to write
    /// are the renderer's, and a feature cannot import another. So the app —
    /// which already connects the canvas to the shell — supplies this, the same
    /// way it supplies everything else that crosses that line.
    ///
    /// Takes the evaluated sprites and the folder, and returns where it wrote
    /// to, or throws.
    @ObservationIgnored
    public var exportHandler: ((_ sprites: [StoryboardSprite], _ folder: URL) throws -> URL)?

    /// Where the last export landed, so the UI can offer to reveal it.
    public private(set) var lastExport: URL?

    /// Why the last export failed, if it did.
    public private(set) var exportError: String?

    public var canExport: Bool { projectFolder != nil && exportHandler != nil }

    @discardableResult
    public func exportStoryboard() -> Bool {
        guard let projectFolder, let exportHandler else { return false }
        do {
            // The same sprites the canvas is drawing, not a fresh evaluation:
            // what was on screen is what should be in the file, and evaluating
            // again is a second chance to disagree.
            lastExport = try exportHandler(evaluated, projectFolder)
            exportError = nil
            return true
        } catch {
            exportError = String(describing: error)
            lastExport = nil
            return false
        }
    }

    /// The clip that was copied, if any.
    ///
    /// Kept in the model rather than the system pasteboard: a clip is a value
    /// only this app understands, and putting it on the system board would put
    /// it in front of every other app for no one's benefit.
    public private(set) var copiedNode: EffectNode?

    public func copySelectedEffect() {
        guard let node = selectedEffect else { return }
        copiedNode = node
    }

    /// Pastes the copied clip onto a track, at a time.
    ///
    /// Onto the selected lane at the playhead by default, which is where a
    /// paste goes in any editor: where you are looking.
    @discardableResult
    public func pasteEffect(
        at time: Double,
        on trackID: EffectTrack.ID? = nil,
    ) -> EffectNode? {
        guard let source = copiedNode,
              let descriptor = library.descriptor(for: source.type)
        else { return nil }

        var node = effects.add(
            descriptor,
            at: max(0, time),
            duration: source.duration,
            on: trackID ?? destinationTrackID,
        )
        node.name = source.name
        node.values = source.values
        node.transform = source.transform
        // A fresh seed, for the same reason a duplicate gets one: the same
        // field drawn twice is not a second effect.
        node.seed = source.seed &+ 0x9E37_79B9
        effects[node.id] = node

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Deletes whatever is selected — a clip if one is, otherwise its lane.
    public func deleteSelection() {
        if let nodeID = selectedNodeID {
            removeEffect(nodeID)
        } else if let trackID = selectedTrackID {
            removeTrack(trackID)
        }
    }

    /// Copies an effect, selecting the copy.
    ///
    /// Selecting it is the point: a duplicate is made to be changed, and having
    /// to hunt for which of two identical clips is the new one is friction in
    /// the way of that.
    @discardableResult
    public func duplicateEffect(_ nodeID: EffectNode.ID) -> EffectNode? {
        let copy = effects.duplicate(nodeID)
        if let copy { selectedNodeID = copy.id }
        effectsChanged()
        return copy
    }

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

    // ─── Keyframes ───────────────────────────────────────────────────────────

    public func setKeyframe(
        _ value: Double,
        for property: TransformProperty,
        at time: Double,
        easing: Easing = .linear,
        on nodeID: EffectNode.ID,
    ) {
        effects.setKeyframe(value, for: property, at: time, easing: easing, on: nodeID)
        effectsChanged()
    }

    public func removeKeyframe(
        _ keyframeID: Keyframe.ID,
        from property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.removeKeyframe(keyframeID, from: property, on: nodeID)
        if selectedKeyframe?.keyframeID == keyframeID { selectedKeyframe = nil }
        effectsChanged()
    }

    /// Changes a selected key's value, keeping it where it is in time.
    public func setKeyframeValue(
        _ value: Double,
        for keyframeID: Keyframe.ID,
        in property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        guard let node = effects[nodeID],
              let key = node.transform[property].keyframes.first(where: { $0.id == keyframeID })
        else { return }
        effects.setKeyframe(value, for: property, at: key.time, easing: key.easing, on: nodeID)
        effectsChanged()
    }

    public func moveKeyframe(
        _ keyframeID: Keyframe.ID,
        in property: TransformProperty,
        to time: Double,
        on nodeID: EffectNode.ID,
    ) {
        effects.moveKeyframe(keyframeID, in: property, to: time, on: nodeID)
        effectsChanged()
    }

    public func setKeyframeEasing(
        _ easing: Easing,
        for keyframeID: Keyframe.ID,
        in property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.setKeyframeEasing(easing, for: keyframeID, in: property, on: nodeID)
        effectsChanged()
    }

    /// Sets a property's resting value.
    ///
    /// What editing a field does when the property is *not* animated. With
    /// animation on, the field lays a keyframe instead — which is the whole
    /// distinction, and collapsing the two planted keys nobody asked for every
    /// time the playhead moved.
    public func setTransformValue(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.setTransformValue(value, for: property, on: nodeID)
        effectsChanged()
    }

    /// Switches a property's animation on or off, keeping its keys.
    public func setAnimationEnabled(
        _ isEnabled: Bool,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        effects.setAnimationEnabled(isEnabled, for: property, on: nodeID, keeping: time)
        effectsChanged()
    }

    public func clearKeyframes(
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        effects.clearKeyframes(for: property, on: nodeID, keeping: time)
        effectsChanged()
    }

    /// Starts animating a property, planting a key at the playhead.
    ///
    /// The first click on a stopwatch has to leave something behind, or nothing
    /// appears to have happened. The key holds the value the property already
    /// had, so switching animation on changes nothing on screen.
    public func beginAnimating(
        _ property: TransformProperty,
        on nodeID: EffectNode.ID,
        at localTime: Double,
    ) {
        guard let node = effects[nodeID] else { return }
        // The key holds the resting value, so switching animation on changes
        // nothing on screen — it only changes what editing the field will do.
        let current = node.transform.value(property, at: localTime)
        effects.setKeyframe(current, for: property, at: localTime, on: nodeID)
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
    public func addFilter(_ descriptor: FilterDescriptor, to nodeID: EffectNode.ID) -> FilterNode? {
        let filter = effects.addFilter(descriptor, to: nodeID)

        // Applying a filter selects the clip it landed on, so its settings are
        // in front of whoever just dropped it.
        selectedNodeID = nodeID
        if let trackID = effects.trackID(of: nodeID) { selectedTrackID = trackID }

        effectsChanged()
        return filter
    }

    public func removeFilter(_ filterID: FilterNode.ID, from nodeID: EffectNode.ID) {
        effects.removeFilter(filterID, from: nodeID)
        effectsChanged()
    }

    public func toggleFilter(_ filterID: FilterNode.ID, in nodeID: EffectNode.ID) {
        effects.toggleFilter(filterID, in: nodeID)
        effectsChanged()
    }

    public func setFilterValue(
        _ value: EffectValue,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        effects.setFilterValue(value, for: parameterID, on: filterID, in: nodeID)
        effectsChanged()
    }

    /// How many sprites one effect produces.
    ///
    /// Evaluated rather than guessed: an emitter's count is a parameter, but a
    /// preset can cap it and a hidden node produces none.
    public func spriteCount(of node: EffectNode) -> Int {
        invalidateCachesIfNeeded()
        return cached(node.id, in: &spriteCounts) { evaluator.evaluate(node).count }
    }

    /// Answers the inspector asks every time it draws, kept until the effects
    /// change.
    ///
    /// Both of these run an effect in full — a 640-particle emitter under a
    /// ×4 loop costs about 12ms between them, and the inspector reads them from
    /// its `body`, which SwiftUI re-runs on every frame the playhead moves.
    /// Selecting such a clip dropped the whole editor to 24fps while nothing
    /// about it had changed. Neither answer can change without an edit, and an
    /// edit already bumps the revision.
    /// Not observed. These are written *during* a view's `body`, and observed
    /// state written while rendering invalidates the view that just read it —
    /// which redraws, writes again, and never settles. The app hung on load.
    /// A cache is not state anyone should redraw for: `effectsRevision` already
    /// says when the answers changed.
    @ObservationIgnored private var spriteCounts: [EffectNode.ID: Int] = [:]
    @ObservationIgnored private var seamSeverities: [EffectNode.ID: Double] = [:]
    @ObservationIgnored private var cacheRevision = -1

    /// Drops both caches when the effects have moved on.
    ///
    /// Kept apart from the read below: clearing touches the same dictionaries
    /// that are held `inout` there, and Swift rejects the overlapping access
    /// outright rather than letting the two disagree.
    private func invalidateCachesIfNeeded() {
        guard cacheRevision != effectsRevision else { return }
        cacheRevision = effectsRevision
        spriteCounts.removeAll(keepingCapacity: true)
        seamSeverities.removeAll(keepingCapacity: true)
    }

    private func cached<Value>(
        _ id: EffectNode.ID,
        in store: inout [EffectNode.ID: Value],
        make: () -> Value,
    ) -> Value {
        if let existing = store[id] { return existing }
        let made = make()
        store[id] = made
        return made
    }

    /// How badly a looped track thins at its seams, from 0 to 1.
    ///
    /// A loop's pass starts from an empty screen, so whatever was still alive
    /// at the end of the previous one is gone. Reported so a fire that flickers
    /// every few seconds has an explanation attached to it.
    public func loopSeamSeverity(for nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID],
              node.filters.contains(where: { $0.isEnabled && $0.type == LoopFilter.descriptor.type })
        else { return 0 }

        // Measured before the loop wraps them: afterwards the commands live in
        // a loop body and every sprite looks like it runs the whole span.
        invalidateCachesIfNeeded()
        return cached(nodeID, in: &seamSeverities) {
            var bare = node
            bare.filters = []
            return LoopFilter.seamSeverity(of: evaluator.evaluate(bare))
        }
    }

    /// How long a clip on this track actually runs, once its filters are
    /// applied.
    public func duration(of clipDuration: Double, on nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return clipDuration }
        return evaluator.duration(of: clipDuration, on: node)
    }

    /// How much a track's filters multiply its sprite count.
    ///
    /// Surfaced so a glow over a large emitter can be seen for what it is —
    /// a file osu! will not open — while it can still be turned down.
    public func spriteMultiplier(for nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return 1 }
        return evaluator.spriteMultiplier(for: node)
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
        hasUnsavedChanges = true
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
