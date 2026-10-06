import Foundation
import StoryboardCore

/// The sprites each clip produced last pass, so an edit only re-runs the clip
/// it touched.
///
/// Every clip in the project was evaluated on every edit, and on a real project
/// that is nearly all of the cost: measured on one of 17 nodes — 14 of them
/// scripts — a pass took 847ms, of which a background image with nothing but a
/// scale and a fade contributed under 1ms. Resizing that image paid for
/// fourteen scripts to be run again, and a script's own work is irreducible
/// (measured on a 17KB one: building its JS context 0.42ms, parsing 0.33ms,
/// **running it 142ms**). The only lever left is not doing the work when
/// nobody asked for it.
///
/// ## What makes an entry stale
///
/// `EffectEvaluator.evaluate(_ node:)` is pure over two things: the node, and
/// what the evaluator and the global seams hold. So an entry survives exactly
/// while both are unchanged — and this type deliberately checks only the first.
///
/// The second is not guessed at. A node draws differently without changing
/// itself in four ways, and every one of them already reaches the model:
///
/// | What moved | How it arrives |
/// |---|---|
/// | The audio loaded — spectrum, lyrics | `inputsChanged()` |
/// | The tempo arrived | `beat` didSet |
/// | A script was edited on disk | `reloadScripts()` |
/// | The node itself | `effectsChanged(node:)` |
///
/// The first three call `effectsChanged()` with **no node named**, which is
/// already the project's word for "anything could have moved" — the same
/// reading `invalidateCachesIfNeeded` and the tail pass make. So the rule is
/// one line: a named edit drops that node, an unnamed one drops the lot.
///
/// Deriving staleness from the inputs instead — hashing the beat, the analyser,
/// every script's source — would be a second answer to a question the model
/// already answers, and the two would drift. The one that drifts silently here
/// is the one that keeps showing sprites the document no longer produces.
///
/// ## Why it is a reference, and locked
///
/// Every edit cancels the pass before it — a drag is dozens of edits in a row,
/// and only the last one is allowed to finish. Carried by value and handed back
/// on completion, the cache is therefore filled **only by passes that survive**,
/// so a run of quick edits keeps throwing away exactly the work it just paid
/// for: measured, entries stayed at zero through an entire sequence and every
/// clip was re-evaluated every time.
///
/// So entries are written as each clip is evaluated, by whichever pass is
/// running. That work is valid no matter what happens to the pass that produced
/// it — a clip's sprites are a function of the clip, and a cancelled pass
/// evaluated the same node the next one will ask for.
final class EvaluationCache: @unchecked Sendable {
    /// Bakes the storyboard camera into one lane's sprites. `CameraTransform`
    /// in the app; a seam so tests can count how often a lane is baked, which
    /// is the whole point of caching it and invisible in the output.
    typealias Bake = @Sendable (
        _ camera: StoryboardCamera,
        _ lane: [StoryboardSprite],
        _ z: Double,
        _ followsCamera: Bool,
    ) -> [StoryboardSprite]

    init(bake: @escaping Bake = { camera, lane, z, follows in
        CameraTransform.apply(camera, to: lane, z: z, followsCamera: follows)
    }) {
        self.bake = bake
    }

    private let bake: Bake

    /// What one clip produced, before its track stamped its layer on.
    ///
    /// Stored pre-layer because that is what `evaluate(_ node:)` returns and
    /// what the track overwrites immediately afterwards — so a clip dragged to
    /// another lane takes its new layer from the track, exactly as it did with
    /// no cache at all. Keeping post-layer sprites would need a second key and
    /// would serve the old lane's layer for one frame.
    private struct Entry {
        /// The node as `drawingKey` renders it, not as it was stored.
        let node: EffectNode
        let sprites: [StoryboardSprite]
        /// Unique to this evaluation, so a lane can tell whether a clip on it
        /// was re-run without comparing what the clip produced.
        let serial: UInt64
        /// How far past its block one pass is still drawing — see
        /// `measure(_:sprites:using:)`.
        let tail: Double
        /// How badly a loop's seam jumps, for a clip that loops.
        let seam: Double?
    }

    /// Everything a lane's baked sprites are a function of.
    ///
    /// The clips enter as the serials of their entries, not as the nodes: an
    /// entry is replaced whenever its clip is evaluated again — a named edit,
    /// an unnamed one that dropped the lot — so a new serial is exactly "this
    /// clip may draw differently now", decided in the one place that already
    /// decides it. Comparing the nodes instead would miss an unnamed edit
    /// (the audio loading, a script changing on disk), where the node is the
    /// same and its output is not.
    private struct LaneKey: Equatable {
        let serials: [UInt64]
        let layer: Layer
        let camera: StoryboardCamera
        let z: Double
        let followsCamera: Bool
    }

    private struct LaneEntry {
        let key: LaneKey
        let sprites: [StoryboardSprite]
    }

    private let lock = NSLock()
    private var entries: [EffectNode.ID: Entry] = [:]
    /// Lanes with the camera baked in, by track.
    ///
    /// Baking was the cost of every edit, not evaluating: measured on a real
    /// project (38 clips, a rotation-keyed camera, 4,240 sprites), stretching
    /// one shape cost 0.9ms of evaluation and 4,120ms of re-baking every lane
    /// in debug — 3,286ms of it into a script lane the edit never touched.
    private var lanes: [EffectTrack.ID: LaneEntry] = [:]
    private var nextSerial: UInt64 = 0

    /// Drops what an edit could have moved.
    ///
    /// - Parameter node: the clip the edit named, or `nil` when it named none.
    func invalidate(node: EffectNode.ID?) {
        lock.lock()
        defer { lock.unlock() }

        guard let node else {
            entries.removeAll(keepingCapacity: true)
            // Would miss on their own — every clip gets a new serial — but they
            // hold every baked sprite, so they go now rather than one pass later.
            lanes.removeAll(keepingCapacity: true)
            return
        }
        entries[node] = nil
    }

    /// Forgets clips the document no longer holds.
    ///
    /// Kept apart from evaluating, because a pass may be cancelled halfway and
    /// must not conclude anything about the clips it never reached. Called from
    /// the model, which knows the document is settled.
    ///
    /// This is about memory, not correctness: ids are never reused — both `add`
    /// and `duplicate` mint a fresh UUID — so a stale entry can only be dead
    /// weight, never a wrong answer. Dead weight worth dropping all the same,
    /// since an entry holds every sprite a clip produced and a session deletes
    /// plenty of them.
    func prune(keeping living: Set<EffectNode.ID>) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { living.contains($0.key) }
    }

    /// Evaluates a document, reusing the clips that have not changed.
    ///
    /// The whole document is walked either way — what is saved is the work
    /// inside each clip, not the walk. Tracks are honoured exactly as
    /// `EffectEvaluator.evaluate(_ document:)` honours them, because a lane's
    /// visibility and layer belong to the lane and not to what is cached.
    ///
    /// - Parameter applyingCamera: `false` for the world as it is before the
    ///   storyboard camera sees it — what the canvas shows while the camera is
    ///   being edited, with the camera's frame drawn over it.
    func sprites(
        for document: EffectDocument,
        using evaluator: EffectEvaluator,
        applyingCamera: Bool = true,
    ) -> [StoryboardSprite] {
        var produced: [StoryboardSprite] = []

        for track in document.tracks {
            // A cancelled pass stops here rather than running to the end.
            //
            // Its result is thrown away by whoever cancelled it, and opening a
            // project starts several passes in a row: one that kept going
            // competed for cores with the pass whose answer is wanted. What it
            // already wrote stays — every entry is keyed by the node it came
            // from, so it is valid whatever happens to the pass.
            if Task.isCancelled { return produced }

            // Every clip is asked for even on a hidden lane: its entries have to
            // survive, or showing the lane again re-runs every script on it.
            var clips: [(sprites: [StoryboardSprite], serial: UInt64)] = []
            for node in track.nodes {
                if Task.isCancelled { return produced }
                clips.append(self.sprites(for: node, using: evaluator))
            }
            guard track.isVisible else { continue }

            // The lane owns the layer, so everything on it takes that layer —
            // the same stamp `evaluate(_ track:)` applies, and the reason
            // entries are stored before it.
            let stamp = { () -> [StoryboardSprite] in
                clips.flatMap(\.sprites).map { sprite in
                    var placed = sprite
                    placed.layer = track.layer
                    return placed
                }
            }

            guard applyingCamera else {
                produced += stamp()
                continue
            }

            // The camera is baked after the clips come out of the cache, and
            // the bake is remembered per lane: an edit to one clip re-bakes
            // only the lane it sits on, and a camera edit — which changes the
            // key of every lane that follows it — re-bakes those and runs no
            // clip.
            let key = LaneKey(
                serials: clips.map(\.serial),
                layer: track.layer,
                camera: document.camera,
                z: track.z,
                followsCamera: track.followsCamera,
            )
            lock.lock()
            let cached = lanes[track.id]
            lock.unlock()
            if let cached, cached.key == key {
                produced += cached.sprites
                continue
            }

            let baked = bake(document.camera, stamp(), track.z, track.followsCamera)
            // Safe from a pass that is later cancelled, for the same reason a
            // clip's entry is: the key names exactly the inputs it came from.
            lock.lock()
            lanes[track.id] = LaneEntry(key: key, sprites: baked)
            lock.unlock()
            produced += baked
        }

        if applyingCamera {
            // Memory, not correctness: a deleted lane's key can never match.
            let living = Set(document.tracks.map(\.id))
            lock.lock()
            lanes = lanes.filter { living.contains($0.key) }
            lock.unlock()
        }

        return produced
    }

    /// One clip, remembered or evaluated, recorded either way.
    ///
    /// The lock is released across the evaluation rather than held over it:
    /// running a script can take hundreds of milliseconds, and holding a lock
    /// through that would make two passes queue behind each other for work one
    /// of them is about to have cancelled.
    private func sprites(
        for node: EffectNode,
        using evaluator: EffectEvaluator,
    ) -> (sprites: [StoryboardSprite], serial: UInt64) {
        // Compared against the node as it was, not against a revision counter.
        // A counter says something in the project moved; the node says whether
        // *this* clip did — and an edit that names no clip still leaves most of
        // them untouched.
        lock.lock()
        let cached = entries[node.id]
        lock.unlock()

        let key = Self.drawingKey(node)
        if let cached, cached.node == key { return (cached.sprites, cached.serial) }

        let sprites = evaluator.evaluate(node)
        let (tail, seam) = Self.measure(node, sprites: sprites, using: evaluator)

        // Written as it is produced, not handed back when the pass ends. Every
        // edit cancels the pass before it, so a result kept until completion is
        // a result a run of quick edits never keeps at all.
        //
        // Safe from a pass that is later cancelled: what is stored is keyed by
        // the node it was evaluated from, so a stale document cannot leave an
        // entry that answers for a node it did not produce.
        lock.lock()
        nextSerial &+= 1
        let serial = nextSerial
        entries[node.id] = Entry(
            node: key, sprites: sprites, serial: serial, tail: tail, seam: seam,
        )
        lock.unlock()

        return (sprites, serial)
    }

    /// The clips whose remembered sprites no longer match the document — the
    /// ones the next pass will run, and so the ones to mark as catching up.
    func staleNodes(in document: EffectDocument) -> Set<EffectNode.ID> {
        lock.lock()
        defer { lock.unlock() }
        return Set(document.nodes.lazy.filter { node in
            self.entries[node.id]?.node != Self.drawingKey(node)
        }.map(\.id))
    }

    /// Each clip's tail and loop seam, as measured when its sprites were made.
    ///
    /// Read after a pass completes, when every clip in the document has an
    /// entry. Kept on the entry rather than measured in a separate sweep, so a
    /// tail can never describe a different version of the clip than the
    /// sprites beside it do.
    func measurements(
        for document: EffectDocument,
    ) -> (tails: [EffectNode.ID: Double], seams: [EffectNode.ID: Double]) {
        lock.lock()
        defer { lock.unlock() }
        var tails: [EffectNode.ID: Double] = [:]
        var seams: [EffectNode.ID: Double] = [:]
        for node in document.nodes {
            guard let entry = entries[node.id] else { continue }
            tails[node.id] = entry.tail
            if let seam = entry.seam { seams[node.id] = seam }
        }
        return (tails, seams)
    }

    /// How far past its own block one pass of a clip is still drawing, and —
    /// for a clip that loops — how badly the seam jumps.
    ///
    /// Read off the sprites rather than derived from the parameters: life,
    /// life randomness, emission mode and every filter move it, and a formula
    /// chasing all of those would drift from what the evaluator produces.
    ///
    /// A clip with no loop is measured off the sprites just produced, which
    /// are exactly one pass. This used to evaluate every clip a second time to
    /// get the same sprites — every script ran twice per edit. Only a loop
    /// needs its own run: afterwards the commands live in a loop body and
    /// every sprite looks like it runs the whole span.
    static func measure(
        _ node: EffectNode,
        sprites: [StoryboardSprite],
        using evaluator: EffectEvaluator,
    ) -> (tail: Double, seam: Double?) {
        let loops = node.filters.contains { $0.type == LoopFilter.descriptor.type }

        var seam: Double?
        if node.filters.contains(where: { $0.isEnabled && $0.type == LoopFilter.descriptor.type }) {
            var bare = node
            bare.filters = []
            seam = LoopFilter.seamSeverity(of: evaluator.evaluate(bare))
        }

        var unlooped = node
        unlooped.filters = node.filters.filter { $0.type != LoopFilter.descriptor.type }
        let pass = loops ? evaluator.evaluate(unlooped) : sprites

        var last = unlooped.endTime
        for sprite in pass {
            for command in sprite.commands {
                last = max(last, command.endTime)
            }
            // A loop keeps its commands in the body, so the group's own span
            // is what plays.
            for loop in sprite.loops {
                let body = loop.commands.map(\.endTime).max() ?? 0
                last = max(last, loop.startTime + body * Double(loop.loopCount))
            }
        }
        return (max(0, (last - node.startTime) - unlooped.duration), seam)
    }

    /// The node with the fields that do not reach a sprite flattened out.
    ///
    /// Compared whole rather than field by field, deliberately. A list of the
    /// fields that *do* matter is a list the next field added has to be
    /// remembered in — and forgetting one there serves sprites the document no
    /// longer produces, silently, which is worse than having no cache at all.
    /// Normalising inverts that: a new field is compared by default, and only
    /// one deliberately named here is ignored.
    ///
    /// Two qualify. A name is a label on the timeline, and a lock refuses edits
    /// — neither is read by anything that draws. Renaming a clip is the common
    /// one: it reaches the model as `appearanceChanged()`, which does not even
    /// re-evaluate, so a rename that dropped the entry would cost the clip its
    /// cached work on the *next* edit, for a change that draws nothing.
    private static func drawingKey(_ node: EffectNode) -> EffectNode {
        var key = node
        key.name = ""
        key.isLocked = false
        // Layers are nodes too, and carry the same two fields.
        key.layers = key.layers.map(drawingKey)
        return key
    }
}
