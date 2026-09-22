import Foundation
import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// Counts how often each clip is actually evaluated.
///
/// The whole point of the cache is work *not* done, and nothing about the
/// sprites says whether they were produced or remembered — a cache that never
/// hits draws exactly the same picture. So these tests count runs, which is the
/// only thing that can tell the two apart.
private final class RunCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[name, default: 0] += 1
    }

    func count(_ name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name] ?? 0
    }

    var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        counts.removeAll()
    }
}

/// A stand-in for an expensive effect: it draws one sprite and tallies the run.
private struct CountedEffect: Effect {
    static let descriptor = EffectDescriptor(
        type: "counted",
        name: "Counted",
        category: .generate,
        systemImage: "number",
        parameters: [],
    )

    let counter: RunCounter

    func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        // Tallied by id, never by name. A name is normalised out of the cache
        // key on purpose — it reaches nothing that draws — so counting by name
        // asks about a clip the cache has no way to distinguish, and an earlier
        // version of these tests reported a clip as "never run" when what had
        // happened was that it was correctly served from cache.
        //
        counter.record(context.node.id)
        var sprite = StoryboardSprite(
            id: context.node.id,
            layer: .foreground,
            origin: .centre,
            filePath: "counted.png",
            defaultX: 320,
            defaultY: 240,
        )
        sprite.commands = [
            Command(
                easing: .linear,
                startTime: 0,
                endTime: context.duration,
                payload: .fade(start: 1, end: 1),
            ),
        ]
        return [sprite]
    }
}

/// An edit re-runs the clip it touched, and nothing else.
///
/// Measured on a real project of 17 nodes — 14 of them scripts — a pass cost
/// 847ms, of which a background image with a scale and a fade contributed under
/// 1ms. Resizing that image paid for fourteen scripts to run again.
@MainActor
@Suite("Evaluation cache")
struct EvaluationCacheTests {
    /// A shell whose effects count their own runs.
    private func shell(_ counter: RunCounter) -> EditorShellModel {
        EditorShellModel(library: EffectLibrary(effects: [CountedEffect(counter: counter)]))
    }

    /// Two clips, with the cache warm for both.
    ///
    /// Awaited after **every** edit, not once at the end: each edit cancels the
    /// pass before it, so a run of them leaves the cache holding whatever the
    /// last surviving pass saw — which is the clips as they were several edits
    /// ago. That is correct behaviour, and it makes for a test that measures
    /// nothing.
    private func warmedPair(_ shell: EditorShellModel) async -> (EffectNode, EffectNode) {
        let a = shell.addEffect(CountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        let b = shell.addEffect(CountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        return (a, b)
    }

    @Test("editing one clip does not re-run the others")
    func editRunsOnlyTheEditedClip() async {
        let counter = RunCounter()
        let shell = shell(counter)

        let (a, b) = await warmedPair(shell)
        counter.reset()

        shell.resizeEffect(a.id, startTime: 0, duration: 4000)
        await shell.awaitEvaluation()

        #expect(counter.count(a.id) >= 1, "the edited clip has to be re-run")
        #expect(counter.count(b.id) == 0,
                "an untouched clip was evaluated \(counter.count(b.id)) times")
    }

    /// Renaming a clip does not cost it its cached work.
    ///
    /// A name is a label on the timeline and reaches nothing that draws — it
    /// arrives as `appearanceChanged()`, which does not even re-evaluate. But
    /// it *is* part of the node, so comparing nodes whole made a rename drop
    /// the entry, and the next edit paid to run the clip again for a change
    /// that drew nothing.
    @Test("renaming a clip keeps its cached sprites")
    func renameKeepsTheEntry() async {
        let counter = RunCounter()
        let shell = shell(counter)

        let (a, b) = await warmedPair(shell)
        shell.renameEffect(b.id, to: "Renamed")
        await shell.awaitEvaluation()
        counter.reset()

        // An edit on the *other* clip, so the renamed one has no reason of its
        // own to run — unless the rename cost it its entry.
        shell.resizeEffect(a.id, startTime: 0, duration: 4000)
        await shell.awaitEvaluation()

        #expect(counter.count(b.id) == 0,
                "a renamed clip lost its entry and was re-run \(counter.count(b.id)) times")
    }

    /// The picture has to be the same whether it was produced or remembered.
    ///
    /// The risk a cache buys is drawing something the document no longer says,
    /// and that is invisible from the sprite count alone — so this compares the
    /// sprites themselves against a shell that has nothing remembered.
    @Test("cached sprites match a cold evaluation")
    func cachedOutputMatchesCold() async {
        let warm = shell(RunCounter())
        let node = warm.addEffect(CountedEffect.descriptor, at: 0)
        _ = warm.addEffect(CountedEffect.descriptor, at: 1000)
        await warm.awaitEvaluation()
        warm.resizeEffect(node.id, startTime: 500, duration: 2500)
        let warmSprites = await warm.settledSprites()

        // The same document, built from scratch, so nothing is remembered.
        let cold = shell(RunCounter())
        let coldNode = cold.addEffect(CountedEffect.descriptor, at: 0)
        _ = cold.addEffect(CountedEffect.descriptor, at: 1000)
        cold.resizeEffect(coldNode.id, startTime: 500, duration: 2500)
        let coldSprites = await cold.settledSprites()

        #expect(warmSprites.count == coldSprites.count)
        #expect(
            warmSprites.flatMap { $0.commands.map(\.timing.endTime) }
                == coldSprites.flatMap { $0.commands.map(\.timing.endTime) },
            "a remembered clip drew something a cold pass does not",
        )
    }

    /// A seam every effect reads moved, so every answer is stale.
    ///
    /// `inputsChanged` is how the loaded audio and the arriving tempo reach the
    /// effects that read them. It names no clip on purpose — and it used to
    /// inherit whatever the last edit had named, which was harmless only while
    /// a pass evaluated everything regardless.
    @Test("an unnamed edit re-runs every clip")
    func inputsChangedRunsEverything() {
        let counter = RunCounter()
        let evaluator = EffectEvaluator(
            library: EffectLibrary(effects: [CountedEffect(counter: counter)]),
        )
        let cache = EvaluationCache()

        var document = EffectDocument()
        let lane = document.addTrack(layer: .foreground)
        _ = document.add(CountedEffect.descriptor, at: 0, duration: 2000, on: lane.id)
        _ = document.add(CountedEffect.descriptor, at: 3000, duration: 2000, on: lane.id)
        _ = cache.sprites(for: document, using: evaluator)
        #expect(counter.total == 2, "both clips evaluated on a cold cache")

        // What `inputsChanged` does: no clip is named, because the seam that
        // moved is one every effect reads.
        cache.invalidate(node: nil)
        counter.reset()
        _ = cache.sprites(for: document, using: evaluator)

        // Exactly two, not "at least one": with the invalidation removed the
        // count is zero, and with it the clips run again even though neither
        // changed — which is the whole point, since what changed is underneath
        // them.
        #expect(counter.total == 2,
                "\(2 - counter.total) clip(s) kept a result from before the inputs moved")
    }

    /// `inputsChanged` must reach the cache as an edit naming no clip.
    ///
    /// The other half of the guard above, and the half the cache cannot see:
    /// what the loaded audio and the arriving tempo move is a seam every effect
    /// reads, so naming a clip would refresh one and leave the rest drawing
    /// what they produced before the song existed. It used to inherit whatever
    /// the last edit had named — harmless only while a pass evaluated
    /// everything regardless of the name.
    @Test("inputsChanged names no clip")
    func inputsChangedNamesNoClip() async {
        let counter = RunCounter()
        let shell = shell(counter)

        let (a, b) = await warmedPair(shell)
        shell.resizeEffect(a.id, startTime: 0, duration: 4000)
        await shell.awaitEvaluation()
        counter.reset()

        shell.inputsChanged()
        await shell.awaitEvaluation()

        // Both, not just the one the previous edit had named.
        #expect(counter.count(a.id) >= 1, "A kept a result from before the inputs moved")
        #expect(counter.count(b.id) >= 1, "B kept a result from before the inputs moved")
    }

    /// Every field that reaches a sprite has to make the entry stale.
    ///
    /// The cache compares a node with `name` and `isLocked` flattened out,
    /// because neither reaches anything that draws. The danger is normalising
    /// one that does: the clip would then be served its old sprites after a
    /// real change, silently, which is far worse than having no cache.
    ///
    /// So each field is moved in turn and the cache asked again. Verified by
    /// flattening `transform` as well — a whole suite of 1,291 tests passed
    /// with that in, because moving a clip is something nothing else measures
    /// through the cache.
    @Test("every field that draws invalidates the entry", arguments: [
        "startTime", "duration", "seed", "values", "transform", "filters", "layer",
    ])
    func everyDrawingFieldInvalidates(field: String) {
        let counter = RunCounter()
        let evaluator = EffectEvaluator(
            library: EffectLibrary(effects: [CountedEffect(counter: counter)]),
        )
        let cache = EvaluationCache()

        var document = EffectDocument()
        let lane = document.addTrack(layer: .foreground)
        let node = document.add(CountedEffect.descriptor, at: 0, duration: 2000, on: lane.id)
        _ = cache.sprites(for: document, using: evaluator)
        #expect(counter.total == 1)

        guard var moved = document[node.id] else { Issue.record("clip vanished"); return }
        switch field {
        case "startTime": moved.startTime += 500
        case "duration": moved.duration += 500
        case "seed": moved.seed &+= 1
        case "values": moved.values["anything"] = .number(1)
        case "transform": moved.transform[value: .scaleX] = 2
        case "filters": moved.filters.append(FilterNode(id: "f1", type: "glow"))
        case "layer": moved.layer = .overlay
        default: Issue.record("unknown field \(field)"); return
        }
        document[node.id] = moved

        counter.reset()
        _ = cache.sprites(for: document, using: evaluator)

        #expect(counter.total == 1,
                "changing \(field) served the clip's old sprites")
    }

    /// Hiding a clip has to stop it drawing.
    ///
    /// Its own case rather than one more row above, because it is the one
    /// drawing field the run counter cannot see: a hidden node returns nothing
    /// *without* calling the effect, so the tally stays put whether the entry
    /// went stale or was served. Measured on the sprites instead.
    @Test("hiding a clip invalidates its entry")
    func hidingAClipInvalidates() {
        let counter = RunCounter()
        let evaluator = EffectEvaluator(
            library: EffectLibrary(effects: [CountedEffect(counter: counter)]),
        )
        let cache = EvaluationCache()

        var document = EffectDocument()
        let lane = document.addTrack(layer: .foreground)
        let node = document.add(CountedEffect.descriptor, at: 0, duration: 2000, on: lane.id)
        #expect(cache.sprites(for: document, using: evaluator).count == 1)

        guard var hidden = document[node.id] else { Issue.record("clip vanished"); return }
        hidden.isVisible = false
        document[node.id] = hidden

        #expect(cache.sprites(for: document, using: evaluator).isEmpty,
                "a hidden clip was served its old sprites")
    }

    /// A clip moved to another lane takes that lane's layer.
    ///
    /// Entries are stored before the track stamps its layer on, so this is what
    /// says the stamp still happens on a cache hit — a clip dragged between
    /// lanes would otherwise keep drawing in the old one.
    @Test("a cached clip takes its new lane's layer")
    func cachedClipFollowsItsLane() async {
        let shell = shell(RunCounter())
        let node = shell.addEffect(CountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        let before = await shell.settledSprites().first?.layer

        // Moved to a lane with a different layer, without touching the clip.
        let lane = shell.addTrack()
        shell.setLayer(.overlay, on: lane.id)
        shell.moveEffect(node.id, toTrack: lane.id)
        let after = await shell.settledSprites().first?.layer

        #expect(before != .overlay,
                "the starting lane has to differ for this to measure anything")
        #expect(after == .overlay, "a cached clip kept its old lane's layer")
    }

    /// A hidden lane keeps the entries of what sits on it.
    ///
    /// The cheap reading is to skip evaluating a hidden lane's clips, since it
    /// draws nothing — and that drops their entries, so showing the lane again
    /// re-runs every script on it. Toggling a lane is how someone learns what
    /// each one contributes, so it is a round trip that happens constantly.
    ///
    /// Measured on the cache itself rather than through the model: hiding a
    /// lane reaches it as `effectsChanged()` with no clip named, which empties
    /// the cache wholesale — correct, and more than the change requires. That
    /// remains the model's reading to refine; what this fixes in place is that
    /// the cache does not throw the entries away on its own.
    @Test("a hidden lane keeps its clips cached")
    func hiddenLaneKeepsItsEntries() {
        let counter = RunCounter()
        let evaluator = EffectEvaluator(
            library: EffectLibrary(effects: [CountedEffect(counter: counter)]),
        )
        let cache = EvaluationCache()

        var document = EffectDocument()
        let lane = document.addTrack(layer: .foreground)
        _ = document.add(CountedEffect.descriptor, at: 0, duration: 2000, on: lane.id)

        #expect(cache.sprites(for: document, using: evaluator).count == 1)
        #expect(counter.total == 1)

        document.toggleVisibility(of: lane.id)
        #expect(cache.sprites(for: document, using: evaluator).isEmpty,
                "a hidden lane draws nothing")

        counter.reset()
        document.toggleVisibility(of: lane.id)

        #expect(cache.sprites(for: document, using: evaluator).count == 1,
                "the lane is visible again")
        #expect(counter.total == 0,
                "showing a lane re-ran \(counter.total) clips that had not changed")
    }

    /// A deleted clip's sprites do not sit in the cache forever.
    ///
    /// About memory rather than correctness — ids are never reused, so a stale
    /// entry can only be dead weight. But an entry holds every sprite a clip
    /// produced, and a session deletes plenty of clips.
    ///
    /// Measured by asking the cache to serve the deleted clip again: an entry
    /// that survived answers without running the effect, and one that was
    /// pruned has to run it. Going through the model cannot tell the two apart
    /// — a deleted clip draws nothing either way.
    @Test("a deleted clip is dropped from the cache")
    func deletedClipIsPruned() {
        let counter = RunCounter()
        let evaluator = EffectEvaluator(
            library: EffectLibrary(effects: [CountedEffect(counter: counter)]),
        )
        let cache = EvaluationCache()

        var document = EffectDocument()
        let lane = document.addTrack(layer: .foreground)
        let node = document.add(CountedEffect.descriptor, at: 0, duration: 2000, on: lane.id)
        _ = cache.sprites(for: document, using: evaluator)
        #expect(counter.total == 1)

        // Deleted, and the cache told what survives — which is what the model
        // does once the document has settled.
        var without = document
        without.remove(node.id)
        cache.prune(keeping: Set(without.nodes.map(\.id)))

        // The original document asked again: the clip is unchanged, so a
        // surviving entry would answer without running the effect.
        counter.reset()
        _ = cache.sprites(for: document, using: evaluator)

        #expect(counter.total == 1, "a deleted clip's entry outlived it")
    }
}
