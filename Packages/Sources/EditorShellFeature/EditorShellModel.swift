import CoreGraphics
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
/// Where an imported file is copied to.
///
/// osu! reads the two places differently, and a file in the wrong one is broken
/// in a way nothing shows until export: the root is the **beatmap's** own art —
/// the background, the video — and `sb/` is the **storyboard's**. Asking is
/// cheaper than importing wrong and untangling it later, which is exactly what
/// happened when the button chose for you.
public enum AssetDestination: String, CaseIterable, Identifiable, Sendable {
    /// The beatmap folder itself: backgrounds and video.
    case root
    /// `sb/`, where a storyboard's images live by convention.
    case storyboard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .root: "Beatmap Root"
        case .storyboard: "Storyboard (sb/)"
        }
    }

    public var detail: String {
        switch self {
        case .root: "Backgrounds and video — what the map itself uses."
        case .storyboard: "Images the storyboard draws."
        }
    }

    /// The subfolder to copy into, relative to the beatmap folder.
    public var relativeFolder: String {
        switch self {
        case .root: ""
        case .storyboard: "sb"
        }
    }
}

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

    /// Which folder the file sits in, for the panel to show.
    ///
    /// The panel used to keep only the last component, so `bg.jpg` at the root
    /// and `sb/bg.jpg` looked identical — and a background imported into the
    /// wrong place was invisible until export time, when it is a nuisance to
    /// untangle. Where a file lives is part of what it *is* here: osu! reads
    /// the root for the map's own art and `sb/` for the storyboard's.
    public var folder: String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory.isEmpty ? "root" : directory
    }

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
    public var selectedNodeID: EffectNode.ID? {
        didSet {
            guard selectedNodeID != oldValue else { return }
            onSelectionChanged?(selectedNodeID)
        }
    }

    /// Told the moment the selection changes.
    ///
    /// A callback rather than something the app reads in a `body`: reading it
    /// there subscribes the window to it, and going through `.task(id:)`
    /// instead put a scheduling hop between the click and the canvas — the
    /// frame that draws the selection box could not run until that hop landed.
    @ObservationIgnored public var onSelectionChanged: ((EffectNode.ID?) -> Void)?

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
    public private(set) var effects = EffectDocument() {
        // Captured here rather than at each of the thirty-odd mutations.
        //
        // A `willSet` sees both sides of every write, whoever made it, so undo
        // cannot be forgotten when an edit is added later — and a gap in an
        // undo stack is worse than no undo at all: it takes the document
        // somewhere the author never was.
        willSet {
            guard isRecordingUndo else { return }
            // One entry per gesture, not per step.
            //
            // A slider dragged across its range writes on every step, and each
            // write copies the whole document — measured at 300KB for a busy
            // project, that is megabytes a second of copying on the main
            // thread, and it is what made a drag stutter as it went.
            //
            // It is also what every editor does: undoing a drag returns to
            // where the drag started, not one pixel back. Fifty undo steps to
            // escape one gesture is a stack nobody can use.
            guard !isCoalescingUndo else { return }
            history.record(effects)
        }
    }

    /// Whether edits are being folded into one undo entry.
    @ObservationIgnored private var isCoalescingUndo = false

    /// Folds every edit until ``endGesture()`` into a single undo step.
    ///
    /// Called when a continuous gesture starts — a slider grabbed, a field
    /// focused, a clip picked up. The first write still records, so the entry
    /// holds the document as it was *before* the gesture.
    public func beginGesture() {
        guard !isCoalescingUndo else { return }
        history.record(effects)
        isCoalescingUndo = true
        isGestureActive = true
    }

    /// Ends a coalesced gesture, so the next edit records again.
    public func endGesture() {
        isCoalescingUndo = false
        isGestureActive = false
        // Straight away on release: the pause is for while a hand is moving,
        // and waiting after it stops is a delay nobody asked for.
        pendingEvaluation?.cancel()
        evaluateNow()
    }

    /// Turned off while undo itself is writing, so stepping back does not
    /// record the step back as an edit — the stack would fill with itself and
    /// a second undo would go nowhere.
    @ObservationIgnored private var isRecordingUndo = true

    /// Undo and redo.
    ///
    /// Not observed: the history changes on every edit and nothing about the
    /// view depends on its contents — only on whether the two commands are
    /// available, which is read at menu time.
    @ObservationIgnored private var history = EditHistory()

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    public func undo() {
        guard let previous = history.undo(from: effects) else { return }
        withoutRecording { effects = previous }
        effectsChanged()
    }

    public func redo() {
        guard let next = history.redo(from: effects) else { return }
        withoutRecording { effects = next }
        effectsChanged()
    }

    private func withoutRecording(_ write: () -> Void) {
        isRecordingUndo = false
        write()
        isRecordingUndo = true
    }
    public let library: EffectLibrary
    public let filters: FilterLibrary
    // A `var` because the beat is set after the map opens: tempo comes off
    // the beatmap, and this feature never opens one.
    private var evaluator: EffectEvaluator

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

        // No clip selected means no clip's parameters.
        //
        // A lane's only effect used to answer here, so a row holding one clip
        // did not need that clip clicked as well. Convenient, and it meant the
        // panel never emptied: after deselecting, it went on offering
        // parameters for something nothing on screen said was chosen. A panel
        // that describes an unselected clip is editing blind, and picking the
        // clip is one click.
        return nil
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
    ///
    /// The last completed pass. A caller that needs the sprites for the
    /// *document as it stands right now* — an export, a test — awaits
    /// ``awaitEvaluation()`` first; one that wants something to draw takes what
    /// is here, because the last good frame is exactly right for a canvas.
    public func evaluateEffects() -> [StoryboardSprite] {
        evaluated
    }

    /// Called whenever a new pass lands, so the canvas can take the sprites
    /// rather than asking for them.
    ///
    /// Pushed rather than pulled because the result no longer arrives when the
    /// edit does: reading a revision counter would tell a view that something
    /// changed at the moment the work *started*, which is a frame of emptiness
    /// before the sprites exist.
    @ObservationIgnored public var onSpritesChanged: (([StoryboardSprite]) -> Void)?

    /// The sprites for the document as it stands, waiting for any pass in
    /// flight.
    ///
    /// What a caller wants when the sprites are the *answer* rather than the
    /// picture — an export, a test. The canvas deliberately does not use this:
    /// there, the last good frame is right.
    public func settledSprites() async -> [StoryboardSprite] {
        await awaitEvaluation()
        return evaluated
    }

    /// Presets available for the effects in the library.
    public var presets: [EffectPreset] {
        // Every effect's presets, filtered to what the library can actually
        // run. The panel groups them by `effectType`, so a new effect's presets
        // appear under it without any UI work.
        (TextEffect.presets + ShapeEffect.presets + EmitterEffect.presets + EmitterEffect.compoundPresets)
            .filter { library.descriptor(for: $0.effectType) != nil }
    }

    /// Presets grouped into the packs they belong to, in a stable order.
    public var packs: [(name: String, presets: [EffectPreset])] {
        let packed = presets.compactMap { preset -> (String, EffectPreset)? in
            guard let pack = preset.pack else { return nil }
            return (pack, preset)
        }

        var order: [String] = []
        var byPack: [String: [EffectPreset]] = [:]
        for (name, preset) in packed {
            if byPack[name] == nil { order.append(name) }
            byPack[name, default: []].append(preset)
        }

        return order.map { ($0, byPack[$0] ?? []) }
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

        // The preset's own layers, each a node in its own right.
        //
        // Built here rather than described in the preset because only this
        // knows how to make an id and a seed — and a seed that repeated across
        // layers would give two of them the same particle field.
        node.layers = preset.layers.enumerated().compactMap { index, layer in
            guard let layerDescriptor = library.descriptor(for: layer.effectType) else {
                return nil
            }
            var child = EffectNode(
                id: "\(node.id)/L\(index)",
                type: layer.effectType,
                name: layer.name,
                layer: node.layer,
                startTime: 0,
                duration: preset.duration,
                seed: EffectNode.layerSeed(from: node.seed, index: index),
                values: layerDescriptor.defaultValues.merging(layer.values) { _, new in new },
            )
            // A layer's position is a transform too, for the same reason the
            // parent's is.
            if case let .number(x) = layer.values[EmitterEffect.Param.x] {
                child.transform[value: .x] = x
            }
            if case let .number(y) = layer.values[EmitterEffect.Param.y] {
                child.transform[value: .y] = y
            }
            return child
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

    /// Where the timeline is looking, kept so it can be saved and restored.
    ///
    /// On the model rather than left in the view: the view's own `@State` is
    /// gone by the time a project is written, and a window someone spent time
    /// arranging is worth reopening as they left it.
    @ObservationIgnored public var timelineView: Project.TimelineView?

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
            // Cleared before the write, and the write itself is not recorded.
            //
            // Undoing into the previous beatmap's document would restore
            // effects belonging to a different map — worse than having no undo
            // at all, because it looks like it worked.
            history.clear()
            withoutRecording { effects = project.document }
            timelineView = project.view
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
            try ProjectFile.write(
                Project(document: effects, view: timelineView),
                toFolder: projectFolder,
            )
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
    /// Renders what something does, as frames, if the app supplies them.
    ///
    /// Provided from outside for the same reason the export is: drawing needs
    /// the renderer, and this feature is layout rather than behaviour. Optional
    /// so the shell runs without it — a panel with no pictures is a panel, a
    /// panel that cannot be built is not.
    /// The song's beat, for effects that follow it.
    ///
    /// Set by whoever owns playback, because the timing comes off the beatmap
    /// and this feature never opens one. An effect asks the evaluator, which
    /// asks this — so a pulse needs no BPM typed into it.
    public var beat: BeatGrid? {
        didSet {
            evaluator.beat = beat
            effectsChanged()
        }
    }

    public var previewImage: ((PreviewSubject) -> [CGImage])?

    public var exportHandler: ((_ sprites: [StoryboardSprite], _ folder: URL) throws -> URL)?

    /// Where the selected clip's pixels are, as the canvas last measured them.
    ///
    /// Supplied by the app rather than worked out here, for the same reason the
    /// preview and the export are: the box comes from the renderer, and a
    /// feature cannot import another. Measured rather than computed because a
    /// clip's transform holds where its *pivot* is, and for anything but a
    /// centred sprite that is a different number from where its pixels land.
    public var selectionBounds: (() -> ClipBounds?)?

    /// Brings image files into the beatmap folder, returning their new
    /// relative paths.
    ///
    /// Supplied by the app: copying a file is the folder's business, and a
    /// feature cannot import another. Returns the paths rather than reloading
    /// on its own so the panel can select what just arrived.
    public var importAssets: ((AssetDestination) -> [String])?

    /// Whether importing is possible — there has to be a folder to copy into.
    public var canImportAssets: Bool { importAssets != nil }

    /// Copies files chosen by the author into the project, and lists them.
    ///
    /// Copied rather than referenced, because osu! reads only what sits in the
    /// beatmap folder: an asset linked from elsewhere works in the editor and
    /// arrives broken in the game — the worst kind of failure, since it looks
    /// finished right up until it ships.
    public func importAssetsFromDisk(into destination: AssetDestination) {
        guard let importAssets else { return }
        let added = importAssets(destination)
        guard !added.isEmpty else { return }

        // Merged rather than replacing: the folder listing was taken when the
        // project opened, and re-walking the whole folder to learn about two
        // files is work for an answer already in hand.
        let merged = Set(folderPaths).union(added)
        folderPaths = merged.sorted()
        rebuildAssets(missing: missingPaths)
    }

    /// A thumbnail for a file in the beatmap folder.
    ///
    /// Supplied by the app for the same reason the preview and the export are:
    /// reading an image is the renderer's business, and a feature cannot import
    /// another. A panel that lists filenames makes you open each one to find
    /// out what it is — the picture *is* the label.
    public var assetThumbnail: ((String) -> CGImage?)?

    /// Thumbnails already loaded, by path.
    ///
    /// Cached because a grid asks for every visible one on every rebuild, and
    /// decoding a PNG per row per frame is the same mistake as evaluating an
    /// effect in a `body`. `nil` inside the dictionary is a remembered failure:
    /// a file that could not be read must not be retried sixty times a second.
    @ObservationIgnored private var thumbnails: [String: CGImage?] = [:]

    /// The thumbnail for a path, loading it once.
    public func thumbnail(for path: String) -> CGImage? {
        if let cached = thumbnails[path] { return cached }
        let image = assetThumbnail?(path)
        thumbnails[path] = image
        return image
    }

    /// Where the last export landed, so the UI can offer to reveal it.
    public private(set) var lastExport: URL?

    /// Why the last export failed, if it did.
    public private(set) var exportError: String?

    public var canExport: Bool { projectFolder != nil && exportHandler != nil }

    // ─── Video ───────────────────────────────────────────────────────────────

    /// Renders the storyboard to a video file, if someone has wired up how.
    ///
    /// Supplied by the app for the same reason the storyboard export is: the
    /// renderer belongs to another feature, and features do not import each
    /// other.
    @ObservationIgnored
    public var videoExportHandler: ((URL, @escaping @Sendable (Double) -> Void) async throws -> Void)?

    /// How far a running video export has got, or `nil` when none is running.
    public private(set) var videoProgress: Double?

    /// Why the last video export failed, if it did.
    public private(set) var videoError: String?

    public var canExportVideo: Bool { videoExportHandler != nil && videoProgress == nil }

    /// The stretch a video needs to cover: from the first sprite to the last.
    ///
    /// Not the song. A storyboard often occupies a fraction of the track, and
    /// rendering the silence around it is minutes of work producing black
    /// frames — a five-minute song is nineteen thousand of them.
    public var videoRange: ClosedRange<Double>? {
        let sprites = evaluated
        guard !sprites.isEmpty else { return nil }

        var lower = Double.greatestFiniteMagnitude
        var upper = -Double.greatestFiniteMagnitude
        for sprite in sprites {
            for command in sprite.commands {
                lower = Swift.min(lower, command.startTime)
                upper = Swift.max(upper, command.endTime)
            }
            for loop in sprite.loops {
                lower = Swift.min(lower, loop.startTime)
                for command in loop.commands {
                    upper = Swift.max(upper, loop.startTime
                        + command.endTime * Double(loop.loopCount))
                }
            }
        }

        guard upper > lower else { return nil }
        // A moment either side, so the first frame is not already mid-fade.
        return Swift.max(0, lower - 500)...(upper + 500)
    }

    public func exportVideo(to url: URL) {
        // The same reason: a video is the output, not the preview.
        guard let videoExportHandler, videoProgress == nil else { return }
        videoProgress = 0
        videoError = nil

        Task { @MainActor in
            do {
                try await videoExportHandler(url) { [weak self] fraction in
                    Task { @MainActor in self?.videoProgress = fraction }
                }
                videoProgress = nil
            } catch {
                videoError = String(describing: error)
                videoProgress = nil
            }
        }
    }

    @discardableResult
    public func exportStoryboard() async -> Bool {
        // Wait for any pending pass, because here the sprites are the output
        // rather than the picture: mid-pass this would write what was on screen
        // a moment ago.
        await awaitEvaluation()
        return exportStoryboardNow()
    }

    private func exportStoryboardNow() -> Bool {
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

    /// Where the playhead is, in project time.
    ///
    /// Kept here because the keyboard shortcuts need it and a `View`'s stored
    /// `currentTime` is captured when its body runs — the shortcut buttons live
    /// in a `.background` that SwiftUI has no reason to rebuild as the clock
    /// moves, so a paste landed at whatever time the editor opened at. Written
    /// each frame by whoever owns playback.
    @ObservationIgnored public var playheadTime: Double = 0 {
        didSet { observedPlayheadTime = playheadTime }
    }

    /// The same value, observed.
    ///
    /// Two properties rather than one because they answer opposite needs: the
    /// playhead marker *must* redraw with the clock, and the inspector must
    /// not. A single observed property would drag every reader along; a single
    /// ignored one would leave the marker frozen.
    public private(set) var observedPlayheadTime: Double = 0

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
        // And its filters, reidentified: the id prefixes the sprites a filter
        // derives, so two nodes sharing it would name the same ones.
        node.filters = source.filters.map { $0.reidentified() }
        // A fresh seed, for the same reason a duplicate gets one: the same
        // field drawn twice is not a second effect.
        node.seed = source.seed &+ 0x9E37_79B9
        // And its layers, re-homed under the new id for the same reason the
        // filters were reidentified.
        node.layers = source.layersRehomed(under: node.id, seed: node.seed)
        effects[node.id] = node

        selectedNodeID = node.id
        effectsChanged()
        return node
    }

    /// Deletes whatever is selected — a clip if one is, otherwise its lane.
    public func deleteSelection() {
        // Most specific first.
        //
        // A selected keyframe used to be invisible here, so pressing Delete
        // while working on one destroyed the whole clip it belonged to — and
        // there is no undo to take that back. What is selected is what gets
        // deleted, and a keyframe is a narrower selection than the clip that
        // holds it.
        if let selection = selectedKeyframe {
            removeKeyframe(
                selection.keyframeID,
                from: selection.property,
                on: selection.nodeID,
            )
            return
        }

        // In keyframe mode the clip is selected only because its keys are being
        // edited. Deleting it from under that is never what the key was aimed
        // at, so it takes leaving the mode first.
        guard keyframeNodeID == nil else { return }

        if let nodeID = selectedNodeID {
            removeEffect(nodeID)
        } else if let trackID = selectedTrackID {
            requestRemoveTrack(trackID)
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
        effectsChanged(node: nodeID)
        return copy
    }

    public func removeEffect(_ nodeID: EffectNode.ID) {
        effects.remove(nodeID)
        if selectedNodeID == nodeID { selectedNodeID = nil }
        effectsChanged(node: nodeID)
    }

    public func setValue(_ value: EffectValue, for parameterID: String, on nodeID: EffectNode.ID) {
        effects.setValue(value, for: parameterID, on: nodeID)
        effectsChanged(node: nodeID)
    }

    /// Sets a parameter on one layer of a compound effect.
    public func setLayerValue(
        _ value: EffectValue,
        for parameterID: String,
        onLayer layerID: EffectNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        effects.setValue(value, for: parameterID, onLayer: layerID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    public func toggleLayerVisibility(_ layerID: EffectNode.ID, in nodeID: EffectNode.ID) {
        effects.toggleLayerVisibility(layerID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    public func moveEffect(_ nodeID: EffectNode.ID, to startTime: Double) {
        effects.move(nodeID, to: startTime)
        effectsChanged(node: nodeID)
    }

    public func moveEffect(_ nodeID: EffectNode.ID, toTrack trackID: EffectTrack.ID) {
        effects.move(nodeID, toTrack: trackID)
        effectsChanged()
    }

    public func resizeEffect(_ nodeID: EffectNode.ID, startTime: Double, duration: Double) {
        effects.resize(nodeID, startTime: startTime, duration: duration)
        effectsChanged(node: nodeID)
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
        effectsChanged(node: nodeID)
    }

    public func removeKeyframe(
        _ keyframeID: Keyframe.ID,
        from property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.removeKeyframe(keyframeID, from: property, on: nodeID)
        if selectedKeyframe?.keyframeID == keyframeID { selectedKeyframe = nil }
        effectsChanged(node: nodeID)
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
        effectsChanged(node: nodeID)
    }

    public func moveKeyframe(
        _ keyframeID: Keyframe.ID,
        in property: TransformProperty,
        to time: Double,
        on nodeID: EffectNode.ID,
    ) {
        effects.moveKeyframe(keyframeID, in: property, to: time, on: nodeID)
        effectsChanged(node: nodeID)
    }

    public func setKeyframeEasing(
        _ easing: Easing,
        for keyframeID: Keyframe.ID,
        in property: TransformProperty,
        on nodeID: EffectNode.ID,
    ) {
        effects.setKeyframeEasing(easing, for: keyframeID, in: property, on: nodeID)
        effectsChanged(node: nodeID)
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
        effectsChanged(node: nodeID)
    }

    /// The transform values a canvas drag started from.
    ///
    /// Held here rather than in the view: a gesture spans many events, and a
    /// `@State` tuple in a `View` struct does not survive between them — so
    /// every frame re-read the value it had just written, compounding each step
    /// until moving cancelled itself out and scaling ran away backwards.
    @ObservationIgnored private var canvasDragOrigin: (
        x: Double, y: Double, scaleX: Double, scaleY: Double
    )?

    /// Records where a canvas drag began, once per gesture.
    private func canvasDragBaseline(for node: EffectNode, at time: Double) -> (
        x: Double, y: Double, scaleX: Double, scaleY: Double
    ) {
        if let canvasDragOrigin { return canvasDragOrigin }
        let local = min(max(0, time - node.startTime), node.duration)
        let origin = (
            x: node.transform.value(.x, at: local),
            y: node.transform.value(.y, at: local),
            scaleX: node.transform.value(.scaleX, at: local),
            scaleY: node.transform.value(.scaleY, at: local)
        )
        canvasDragOrigin = origin
        return origin
    }

    /// Applies a drag from the canvas to the selected clip.
    ///
    /// Deltas are measured against the values the gesture started from, never
    /// the current ones: reading back what the last frame wrote compounds every
    /// step.
    /// Sends the selected clip to a stage landmark.
    ///
    /// The same landmarks a drag snaps to, reached by asking rather than by
    /// aiming: snapping helps once a hand is already close, and this is for
    /// "put it in the middle", which is a thing to state.
    ///
    /// Written as a nudge on top of the clip's current position, because the
    /// transform holds where the pivot is while the box says where the pixels
    /// are — assigning the landmark straight to the position would centre the
    /// pivot instead of the picture.
    public func align(_ alignment: StageSnap.Alignment) {
        guard let nodeID = selectedNodeID,
              let node = effects[nodeID],
              !isLocked(nodeID),
              let box = selectionBounds?()
        else { return }

        let offset = StageSnap.offset(
            toAlign: (minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY),
            alignment,
        )

        if alignment.isHorizontal {
            effects.setTransformValue(
                node.transform[value: .x] + offset.dx, for: .x, on: nodeID,
            )
        } else {
            effects.setTransformValue(
                node.transform[value: .y] + offset.dy, for: .y, on: nodeID,
            )
        }
        effectsChanged()
    }

    /// Whether there is a clip to align, and a measurement to align it by.
    public var canAlign: Bool {
        guard let nodeID = selectedNodeID, !isLocked(nodeID) else { return false }
        return selectionBounds?() != nil
    }

    public func applyCanvasDrag(
        dx: Double,
        dy: Double,
        scaleX: Double,
        scaleY: Double,
        isFinished: Bool,
        at time: Double,
    ) {
        guard let nodeID = selectedNodeID,
              let node = effects[nodeID],
              !isLocked(nodeID)
        else { return }

        _ = canvasDragBaseline(for: node, at: time)

        // Nothing is written until the hand comes up.
        //
        // Every write re-evaluates the clip — thousands of sprites — and
        // re-uploads them to the GPU. Doing that per drag event meant the image
        // was always rebuilding from an edit already superseded by the next
        // one, so the picture lagged behind the pointer and the frame rate came
        // apart. This is the same bargain the timeline already makes when a
        // clip is dragged along its lane: preview locally, commit once.
        guard isFinished else { return }

        let origin = canvasDragBaseline(for: node, at: time)
        var updated = node
        let local = min(max(0, time - node.startTime), node.duration)

        if dx != 0 { write(origin.x + dx, for: .x, on: &updated, at: local) }
        if dy != 0 { write(origin.y + dy, for: .y, on: &updated, at: local) }
        // Both axes, so a uniform corner drag stays uniform and a side drag can
        // stretch one on its own — unless the axes are linked, in which case a
        // side handle scales the pair. The lock has to mean the same thing on
        // the canvas as it does in the panel, or the two disagree about what a
        // side handle does.
        let linkedX = scaleIsLinked && scaleY != 1 ? scaleY : scaleX
        let linkedY = scaleIsLinked && scaleX != 1 ? scaleX : scaleY

        if linkedX != 1 { write(origin.scaleX * linkedX, for: .scaleX, on: &updated, at: local) }
        if linkedY != 1 { write(origin.scaleY * linkedY, for: .scaleY, on: &updated, at: local) }

        effects[nodeID] = updated
        effectsChanged()
        canvasDragOrigin = nil
    }

    /// One transform write, following the same rule the inspector's fields do:
    /// a keyframe when the property animates, the resting value when it does
    /// not.
    private func write(
        _ value: Double,
        for property: TransformProperty,
        on node: inout EffectNode,
        at localTime: Double,
    ) {
        if node.transform[property].isActive {
            _ = node.transform[property].set(value, at: localTime)
        } else {
            node.transform[value: property] = value
        }
    }

    /// Whether the two scale axes move together.
    ///
    /// On by default: scaling uniformly is what "make it bigger" means, and
    /// stretching is the deliberate act. Kept on the model rather than in the
    /// inspector so it survives the panel being rebuilt, which happens on every
    /// frame the playhead moves.
    public var scaleIsLinked = true

    /// Writes one scale axis, and the other with it when they are linked.
    ///
    /// The same number in both, which is what the lock is for: keeping a clip
    /// square while it grows. Carrying a ratio instead sounds cleverer and is
    /// not what anyone asks of a lock — it also read the axis back *after*
    /// writing it, so the ratio came out of the value it had just set and one
    /// axis at 0.3 sent the other to 1.5.
    public func setScale(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        at time: Double,
    ) {
        write(value, for: property, on: nodeID, at: time)
        guard scaleIsLinked else { return }
        write(value, for: property == .scaleX ? .scaleY : .scaleX, on: nodeID, at: time)
    }

    /// One transform write, following the inspector's own rule.
    private func write(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        at time: Double,
    ) {
        guard let node = effects[nodeID] else { return }
        if node.transform[property].isEmpty {
            setTransformValue(value, for: property, on: nodeID)
        } else {
            setKeyframe(value, for: property, at: time, on: nodeID)
        }
    }

    /// Writes a transform property the way an edit from the canvas means it.
    ///
    /// The same rule the inspector's fields follow, and deliberately the one
    /// place both go through: with the property animated this plants a keyframe
    /// at the playhead, and without it this moves the resting value. Two paths
    /// to the same edit would eventually disagree about which one a drag meant.
    ///
    /// This is what makes dragging on the canvas honest — the box moves what
    /// the panel says it moves.
    public func setTransformValueFromCanvas(
        _ value: Double,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        at time: Double,
    ) {
        guard let node = effects[nodeID], !isLocked(nodeID) else { return }

        if node.transform[property].isActive {
            // Local to the clip, like every other keyframe time.
            let local = min(max(0, time - node.startTime), node.duration)
            setKeyframe(value, for: property, at: local, on: nodeID)
        } else {
            setTransformValue(value, for: property, on: nodeID)
        }
    }

    /// Whether a clip cannot be edited, because its lane is locked.
    public func isLocked(_ nodeID: EffectNode.ID) -> Bool {
        guard let trackID = effects.trackID(of: nodeID) else { return false }
        return effects.track(id: trackID)?.isLocked ?? false
    }

    /// Switches a property's animation on or off, keeping its keys.
    public func setAnimationEnabled(
        _ isEnabled: Bool,
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        effects.setAnimationEnabled(isEnabled, for: property, on: nodeID, keeping: time)
        effectsChanged(node: nodeID)
    }

    public func clearKeyframes(
        for property: TransformProperty,
        on nodeID: EffectNode.ID,
        keeping time: Double = 0,
    ) {
        effects.clearKeyframes(for: property, on: nodeID, keeping: time)
        effectsChanged(node: nodeID)
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

    /// - Parameter index: where it lands in document order, or `nil` to put it
    ///   on top. Adding from a row's own menu is asking for a lane *beside that
    ///   one*, so the caller says where.
    @discardableResult
    public func addTrack(at index: Int? = nil) -> EffectTrack {
        let track = effects.addTrack(at: index)
        selectedTrackID = track.id
        selectedNodeID = nil
        effectsChanged()
        return track
    }

    /// The lane a delete is waiting on confirmation for, if any.
    ///
    /// Asking lives in the model rather than in the row that was right-clicked,
    /// because **two** paths delete a track — the menu and the Delete key — and
    /// a confirmation attached to one of them leaves the other destroying work
    /// in silence. That is the path most easily hit by accident.
    public var trackPendingDeletion: EffectTrack?

    /// How many clips would go with it, for the alert to say so.
    public var clipsPendingDeletion: Int {
        trackPendingDeletion?.nodes.count ?? 0
    }

    /// Deletes a lane, asking first when there is work on it.
    ///
    /// An empty lane goes without a word: confirming a delete that destroys
    /// nothing trains people to dismiss the dialog, and the one time it matters
    /// they will dismiss that one too. **There is no undo for this** — a track
    /// with clips is somebody's afternoon.
    public func requestRemoveTrack(_ trackID: EffectTrack.ID) {
        guard let track = effects.track(id: trackID) else { return }
        guard !track.nodes.isEmpty else {
            removeTrack(trackID)
            return
        }
        trackPendingDeletion = track
    }

    /// Goes through with the delete the alert was asking about.
    public func confirmRemoveTrack() {
        guard let track = trackPendingDeletion else { return }
        trackPendingDeletion = nil
        removeTrack(track.id)
    }

    public func cancelRemoveTrack() {
        trackPendingDeletion = nil
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
        // A name is a label; no sprite carries it.
        appearanceChanged()
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

        effectsChanged(node: nodeID)
        return filter
    }

    public func removeFilter(_ filterID: FilterNode.ID, from nodeID: EffectNode.ID) {
        effects.removeFilter(filterID, from: nodeID)
        effectsChanged(node: nodeID)
    }

    public func toggleFilter(_ filterID: FilterNode.ID, in nodeID: EffectNode.ID) {
        effects.toggleFilter(filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    public func setFilterValue(
        _ value: EffectValue,
        for parameterID: String,
        on filterID: FilterNode.ID,
        in nodeID: EffectNode.ID,
    ) {
        effects.setFilterValue(value, for: parameterID, on: filterID, in: nodeID)
        effectsChanged(node: nodeID)
    }

    /// How many sprites one effect produces.
    ///
    /// Evaluated rather than guessed: an emitter's count is a parameter, but a
    /// preset can cap it and a hidden node produces none.
    public func spriteCount(of node: EffectNode) -> Int {
        // Counted off the last completed pass, never evaluated here.
        //
        // The inspector reads this in its `body` to show what a clip costs, and
        // the cache is cleared by the edit that prompted the rebuild — so the
        // read landed on a miss and ran the whole effect *synchronously*.
        // Measured on an Audio Bars clip, that was **1,101 to 1,317ms of
        // frozen window** on every value typed into a field, and the freeze
        // came from a number shown as a hint.
        //
        // The async pass already produces these sprites. A count taken from it
        // is a moment out of date at worst, which is the right trade for a
        // readout that exists to warn about file size.
        evaluated.count { ClipBounds.sprite($0.id, belongsTo: node.id) }
    }

    /// When a clip actually stops playing, tail and loops included.
    ///
    /// Not `node.endTime`, which is where the *clip* ends — the thing a drag
    /// resizes and keyframes are measured against. A particle lives its whole
    /// life from wherever it was born, so an emitter releasing right up to the
    /// last instant has its final ones on screen seconds later; a looped clip
    /// runs several times over. Measured, a five-second Portal under a ×4 loop
    /// plays for thirty.
    ///
    /// The timeline draws this one. Reporting the clip's own end has the block
    /// finish while the effect is still going, which makes the one thing a
    /// timeline exists to show a lie — and it is what someone reads to decide
    /// where the next effect goes.
    ///
    /// Read from the sprites rather than worked out from the parameters: life,
    /// life randomness, emission mode and every filter all move it, and a
    /// second formula tracking all of them would drift from the first.
    public func playbackEnd(of node: EffectNode) -> Double {
        playbackEnd(of: node, key: node.id)
    }

    /// - Parameter key: distinct from the node's id where the caller asks about
    ///   a **modified** copy — `rawTail` strips the loop off before measuring,
    ///   and cached under the plain id that answer would be handed back for the
    ///   looped node too. Same id, different question.
    private func playbackEnd(of node: EffectNode, key: String) -> Double {
        invalidateCachesIfNeeded()
        return cached(key, in: &playbackEnds) {
            let sprites = evaluator.evaluate(node)

            var last = node.endTime
            for sprite in sprites {
                for command in sprite.commands {
                    last = max(last, command.endTime)
                }
                // A loop keeps its commands in the body, so the group's own
                // span is what plays — the commands inside say nothing about
                // how many times round it goes.
                for loop in sprite.loops {
                    let body = loop.commands.map(\.endTime).max() ?? 0
                    last = max(last, loop.startTime + body * Double(loop.loopCount))
                }
            }
            return last
        }
    }

    /// How far past its own block a clip is still drawing, in milliseconds.
    ///
    /// Separate from `duration(of:on:)`, which reports repeats: a tail is the
    /// **same** pass still finishing, a repeat is another one starting. Drawn
    /// as one number, a clip whose particles outlive it grew a ghost for a
    /// repetition that never happens.
    /// How long one pass of a clip lasts, tail included.
    ///
    /// Handed to the timeline rather than left for it to divide out: the repeat
    /// ghosts used to infer the pass length from the total, which only works
    /// while a pass is exactly the clip. Once the tail joined the period that
    /// division started reporting a pass too many, at the wrong stride.
    public func passDuration(of nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return 0 }
        return node.duration + rawTail(of: node)
    }

    /// How many times a clip plays: once, plus whatever a loop adds.
    public func passCount(of nodeID: EffectNode.ID) -> Int {
        guard let node = effects[nodeID] else { return 1 }
        return node.loopRepeats
    }

    // ─── Motion path ─────────────────────────────────────────────────────────

    /// Whether the pen tool is armed.
    ///
    /// A mode rather than a permanent overlay: the path's points sit on top of
    /// the canvas and would swallow clicks meant for the clip underneath, and a
    /// tool that stays armed after it is finished is one that fights the app.
    public var isDrawingPath = false

    /// The path on the selected clip's Motion Path filter, if it has one.
    ///
    /// Nil when there is nothing to edit, which is what the canvas checks
    /// before drawing anything: an editor for a path that does not exist is an
    /// overlay intercepting clicks for no reason.
    public var editablePath: MotionPath? {
        guard let node = selectedEffect,
              let filter = node.filters.first(where: { $0.type == "path" && $0.isEnabled }),
              case let .path(path) = filter.values["path"]
        else { return nil }
        return path
    }

    /// Writes a path back to the selected clip.
    public func setEditablePath(_ path: MotionPath) {
        guard let node = selectedEffect,
              let filter = node.filters.first(where: { $0.type == "path" })
        else { return }
        setFilterValue(.path(path), for: "path", on: filter.id, in: node.id)
    }

    public func tail(of nodeID: EffectNode.ID) -> Double {
        // Read from the last completed pass, never computed here.
        //
        // The timeline asks for this per clip on every rebuild, and the edit
        // that prompts the rebuild invalidates it — so the read landed on a
        // miss and evaluated the whole effect *synchronously*. Measured on an
        // Audio Bars clip, **1,285ms of frozen window** on every value typed.
        //
        // The same bug as `spriteCount`, and the third time this pattern has
        // shown up: a cached answer whose cache is cleared by the very edit
        // that asks for it again is not a cache, it is a synchronous
        // evaluation with extra steps.
        tails[nodeID] ?? 0
    }

    /// How far one pass runs past the clip's own length.
    ///
    /// Measured on a single pass, before any loop multiplies it: a repeat
    /// restarts the whole thing, tail and all, so the overhang is a property of
    /// the pass rather than of the sequence.
    private func rawTail(of node: EffectNode) -> Double {
        var unlooped = node
        unlooped.filters = node.filters.filter { $0.type != "loop" }

        let played = playbackEnd(of: unlooped, key: node.id + "#unlooped") - node.startTime
        return max(0, played - unlooped.duration)
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

    /// How far each clip plays past its own length, from the last pass.
    @ObservationIgnored private var tails: [EffectNode.ID: Double] = [:]
    @ObservationIgnored private var playbackEnds: [EffectNode.ID: Double] = [:]
    @ObservationIgnored private var cacheRevision = -1

    /// Drops both caches when the effects have moved on.
    ///
    /// Kept apart from the read below: clearing touches the same dictionaries
    /// that are held `inout` there, and Swift rejects the overlapping access
    /// outright rather than letting the two disagree.
    private func invalidateCachesIfNeeded() {
        guard cacheRevision != effectsRevision else { return }
        cacheRevision = effectsRevision

        // Only the clip that changed, when the edit named one.
        //
        // These answers cost a full evaluation each, and the timeline asks for
        // one per clip on every rebuild — so clearing all of them meant a
        // keystroke re-evaluated every effect in the project *synchronously*,
        // on the main thread. Twenty clips is twenty emitters run over again to
        // redraw a row that did not change.
        //
        // The same bug this file already documents for `spriteCount`, made
        // again a level along: what is expensive here is not the caching, it is
        // deciding that everything is stale when one thing is.
        guard let edited = lastEditedNode else {
            spriteCounts.removeAll(keepingCapacity: true)
            seamSeverities.removeAll(keepingCapacity: true)
            playbackEnds.removeAll(keepingCapacity: true)
            return
        }

        spriteCounts[edited] = nil
        seamSeverities[edited] = nil
        playbackEnds[edited] = nil
        // The tail is cached under its own key, because it asks a different
        // question of the same id.
        playbackEnds[edited + "#unlooped"] = nil
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

        // The tail first, then the filters.
        //
        // A loop's period is the longest command in its body — the clip **and
        // its tail** — so the next pass only starts once the previous one has
        // finished dying out. Multiplying the bare clip length instead reported
        // the repeats closer together than they actually play, which is what
        // put the ghosts out of step with the sound.
        //
        // Order matters: the tail belongs to one pass, so it goes in before the
        // count multiplies it. `tail(of:)` unwinds the same arithmetic to find
        // the overhang of the last pass, which is the only one that shows.
        let onePass = clipDuration + rawTail(of: node)
        return evaluator.duration(of: onePass, on: node)
    }

    /// How much a track's filters multiply its sprite count.
    ///
    /// Surfaced so a glow over a large emitter can be seen for what it is —
    /// a file osu! will not open — while it can still be turned down.
    public func spriteMultiplier(for nodeID: EffectNode.ID) -> Double {
        guard let node = effects[nodeID] else { return 1 }
        return evaluator.spriteMultiplier(for: node)
    }

    public func setColour(_ colour: TrackColour?, on trackID: EffectTrack.ID) {
        effects.setColour(colour, on: trackID)
        // Not `effectsChanged()`: a track's colour is a label in the editor and
        // reaches no sprite, so re-running every emitter for it is a second of
        // the main thread spent producing exactly what was already on screen.
        appearanceChanged()
    }

    /// Records a change that alters how the editor looks but not what it draws.
    ///
    /// The document still has to be saved and the views still have to redraw —
    /// what it skips is the evaluation, which is the expensive half.
    private func appearanceChanged() {
        effectsRevision &+= 1
        hasUnsavedChanges = true
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
        // A lock refuses edits; it changes nothing about what is drawn.
        appearanceChanged()
    }

    public func raiseTrack(_ trackID: EffectTrack.ID) {
        effects.raiseTrack(trackID)
        effectsChanged()
    }

    public func lowerTrack(_ trackID: EffectTrack.ID) {
        effects.lowerTrack(trackID)
        effectsChanged()
    }

    /// Moves a track to a position in one edit.
    ///
    /// A drag across six lanes used to be five `lowerTrack` calls, and each one
    /// re-evaluated the whole document to reach an arrangement nobody wanted to
    /// stop at. One move, one evaluation.
    public func moveTrack(_ trackID: EffectTrack.ID, toIndex index: Int) {
        effects.moveTrack(trackID, toIndex: index)
        effectsChanged()
    }

    /// Sends a track to the front or the back of the stack.
    ///
    /// The two ends are worth their own commands because they are where people
    /// actually want to go: "put this on top" is one thought, and stepping
    /// there one lane at a time is that thought spelled out five times.
    public func moveTrackToFront(_ trackID: EffectTrack.ID) {
        effects.moveTrack(trackID, toIndex: effects.tracks.count - 1)
        effectsChanged()
    }

    public func moveTrackToBack(_ trackID: EffectTrack.ID) {
        effects.moveTrack(trackID, toIndex: 0)
        effectsChanged()
    }

    /// Signals that something about the effects changed and re-evaluates.
    /// - Parameter node: which clip the edit touched, when it was only one.
    ///   Used so the "catching up" mark lands on that clip rather than on every
    ///   clip in the project — twenty spinners for one edit is both a lie and
    ///   twenty rows rebuilt to tell it.
    private func effectsChanged(node: EffectNode.ID? = nil) {
        effectsRevision &+= 1
        hasUnsavedChanges = true
        lastEditedNode = node
        reevaluate()
    }

    /// Rebuilds the sprites off the main thread.
    ///
    /// Evaluation used to run inline here, which is fine while it is fast and a
    /// frozen window the moment it is not: an emitter under a grid takes tens of
    /// milliseconds, and anything that reads the song takes far longer — a
    /// measured 1,176ms just to seek into an MP3. Every one of those was a
    /// stall someone felt as the app hanging.
    ///
    /// Last one wins. A slider dragged across its range starts an evaluation
    /// per step, and without cancelling the one for value 5 can land after the
    /// one for value 7 — the canvas would settle on a value the document no
    /// longer holds.
    ///
    /// The canvas keeps showing the last good sprites while a new pass runs,
    /// rather than emptying: a clip that blinks out while its numbers are being
    /// adjusted is worse than one a moment out of date, and `evaluatingNodes`
    /// says which clips are still catching up.
    /// Whether a continuous gesture is in flight, so evaluation can wait for a
    /// pause rather than chasing every step.
    @ObservationIgnored private var isGestureActive = false
    @ObservationIgnored private var pendingEvaluation: Task<Void, Never>?

    /// Rebuilds the sprites because something the effects *read* changed,
    /// rather than the document itself.
    ///
    /// An effect can depend on more than its own parameters — Audio Bars reads
    /// the song, Beat Pulse reads the tempo — and those arrive **after** the
    /// project opens. The first evaluation ran without them and its result was
    /// cached, so a bank of bars stayed on its placeholder wave until somebody
    /// happened to nudge a parameter. Nothing was wrong with the analysis; it
    /// was simply never asked again.
    public func inputsChanged() {
        effectsRevision &+= 1
        reevaluate()
    }

    private func reevaluate() {
        // During a gesture, wait for the hand to settle.
        //
        // A slider dragged across its range fires dozens of times a second, and
        // each one starts an evaluation that the next cancels — measured, eight
        // a second at 66ms each, which is half the frame budget spent on work
        // thrown away. Nobody can read a value that changes forty times a
        // second anyway: what a hand wants is the picture where it stopped.
        if isGestureActive {
            pendingEvaluation?.cancel()
            pendingEvaluation = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.evaluateNow() }
            }
            return
        }
        evaluateNow()
    }

    private func evaluateNow() {
        evaluationTask?.cancel()

        let document = effects
        let evaluator = evaluator
        let revision = effectsRevision

        // Only when it actually changes: writing the same value to observed
        // state still invalidates every view reading it, and during a drag that
        // is the whole timeline rebuilt per step for no visible difference.
        //
        // And only the clip that was edited, not every clip in the project.
        // Marking all of them puts a spinner on twenty blocks when one changed
        // — which is both a lie and twenty rows rebuilt to tell it.
        let pending = lastEditedNode.map { Set([$0]) } ?? Set(document.nodes.map(\.id))
        if evaluatingNodes != pending { evaluatingNodes = pending }

        // Detached from the outset, not a main-actor task that hands work off.
        //
        // `Task { }` inherits the actor it was made on, so this one queued
        // *behind* whatever the main thread was doing — measured after a resize
        // gesture, 1,098ms before it even started, against 552ms of actual
        // work. That wait is the pause between letting go of a clip and the
        // spinner appearing.
        evaluationTask = Task.detached(priority: .userInitiated) { [weak self] in
            let sprites = evaluator.evaluate(document)

            guard !Task.isCancelled else { return }

            // Worked out here, off the main thread, because the timeline reads
            // them on every rebuild.
            var measured: [EffectNode.ID: Double] = [:]
            for node in document.nodes {
                var unlooped = node
                unlooped.filters = node.filters.filter { $0.type != "loop" }

                // The same reckoning `playbackEnd` did, moved off the main
                // thread: the last moment anything is still drawn, measured on
                // one pass before a loop multiplies it.
                var last = unlooped.endTime
                for sprite in evaluator.evaluate(unlooped) {
                    for command in sprite.commands {
                        last = max(last, command.endTime)
                    }
                    // A loop keeps its commands in the body, so the group's own
                    // span is what plays.
                    for loop in sprite.loops {
                        let body = loop.commands.map(\.endTime).max() ?? 0
                        last = max(last, loop.startTime + body * Double(loop.loopCount))
                    }
                }

                measured[node.id] = max(0, (last - node.startTime) - unlooped.duration)
            }

            await MainActor.run {
                guard let self, self.effectsRevision == revision else { return }
                self.tails = measured
                self.evaluated = sprites
                if !self.evaluatingNodes.isEmpty { self.evaluatingNodes = [] }
                self.onSpritesChanged?(sprites)
            }
        }
    }

    /// The clip the last edit touched, so only it shows as catching up.
    @ObservationIgnored private var lastEditedNode: EffectNode.ID?

    /// Which clips are being rebuilt right now.
    ///
    /// Shown on the clip rather than as a window-wide spinner: a bar across the
    /// top says the app is busy, which is not the question — what someone wants
    /// to know is whether the thing they just edited has caught up.
    public private(set) var evaluatingNodes: Set<EffectNode.ID> = []

    @ObservationIgnored private var evaluationTask: Task<Void, Never>?

    /// Waits for any pending evaluation to land.
    ///
    /// Needed wherever the sprites are the *output* rather than the picture:
    /// exporting mid-pass would write what was on screen a moment ago, which
    /// was impossible while evaluation was inline and is a real window now.
    /// The canvas does not wait — showing the last good frame is exactly right
    /// there.
    public func awaitEvaluation() async {
        await evaluationTask?.value
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
        usageCounts = counts
        rebuildAssets(missing: missingImagePaths)
    }

    /// How many sprites reference each path, from the last load.
    @ObservationIgnored private var usageCounts: [String: Int] = [:]
    /// Paths a sprite names and the folder does not have.
    @ObservationIgnored private var missingPaths: Set<String> = []

    /// The image files the folder holds, supplied by the app.
    ///
    /// The panel used to list **what the storyboard referenced**, which is a
    /// different question and the wrong one: it answered "what have you used"
    /// where an assets panel is asked "what do you have". So a file sitting in
    /// the folder waiting to be placed never appeared — the one case where
    /// looking at the panel is the whole point.
    ///
    /// It also filled with things that are not the mapper's: the app's own
    /// built-in particles and the hashed glyphs a text effect mints live inside
    /// the binary, so they have no thumbnail to show and no folder to be
    /// dragged from.
    public func loadFolderAssets(_ paths: [String]) {
        folderPaths = paths
        rebuildAssets(missing: missingPaths)
    }

    @ObservationIgnored private var folderPaths: [String] = []

    private func rebuildAssets(missing: Set<String>) {
        missingPaths = missing

        assets = folderPaths
            .map { path in
                AssetItem(
                    id: path,
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    kind: .image,
                    useCount: usageCounts[path] ?? 0,
                    isMissing: missing.contains(path),
                )
            }
            // Most used first, then by name.
            //
            // Use count still leads because it says which files matter to this
            // storyboard, and a folder can hold dozens. The name breaks ties so
            // the unused ones — all zero — are in an order somebody can scan
            // rather than whatever the file system happened to return.
            .sorted { ($0.useCount, $1.name) > ($1.useCount, $0.name) }
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

/// What a library preview is wanted for.
///
/// Outside the model because `@Observable` cannot carry a nested enum — its
/// macro tries to give every member an accessor.
public enum PreviewSubject: Sendable {
    case effect(EffectDescriptor)
    case filter(FilterDescriptor)
    case preset(EffectPreset)
}

