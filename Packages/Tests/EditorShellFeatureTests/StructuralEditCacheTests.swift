import Foundation
import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// Counts runs per clip id. See `EvaluationCacheTests` for why runs, and not
/// sprites, are the only thing that tells a cache hit from a miss.
private final class RunCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func record(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[id, default: 0] += 1
    }

    func count(_ id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[id] ?? 0
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

private struct CountedEffect: Effect {
    static let descriptor = EffectDescriptor(
        type: "counted",
        name: "Counted",
        category: .generate,
        systemImage: "number",
        parameters: [],
    )

    let counter: RunCounter
    /// Cancels the pass that runs it, so a test can cancel mid-lane — after
    /// one clip and before the next.
    var cancelsPass = false

    func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        counter.record(context.node.id)
        if cancelsPass { withUnsafeCurrentTask { $0?.cancel() } }
        var sprite = StoryboardSprite(
            id: context.node.id,
            layer: .foreground,
            origin: .centre,
            filePath: "counted.png",
            defaultX: 320,
            defaultY: 240,
        )
        sprite.commands = [
            Command(easing: .linear, startTime: 0, endTime: context.duration, payload: .fade(start: 1, end: 1)),
        ]
        return [sprite]
    }
}

/// An edit that changes the document's shape — adding, deleting, hiding a
/// lane — names no single clip, and used to be read as "anything could have
/// moved": the whole cache was dropped and every clip ran again.
///
/// Measured on a real project (80 clips, 3 scripts): placing one plain image
/// took **12.5s** in debug and put a spinner on all 81 blocks, against 0.67s
/// for moving that same image. The cache compares each clip whole, so the
/// clips such an edit did not touch are still exactly right; only what every
/// effect *reads* — the song, the tempo — is a reason to drop them all.
@MainActor
@Suite("Structural edits and the cache")
struct StructuralEditCacheTests {
    private func shell(_ counter: RunCounter) -> EditorShellModel {
        EditorShellModel(library: EffectLibrary(effects: [CountedEffect(counter: counter)]))
    }

    private func warmedPair(_ shell: EditorShellModel) async -> (EffectNode, EffectNode) {
        let a = shell.addEffect(CountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        let b = shell.addEffect(CountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        return (a, b)
    }

    /// Exactly once, not "at least once": the tail used to be measured by a
    /// second evaluation of a clip whose sprites the cache had just produced,
    /// so every clip — every script — ran twice.
    @Test("adding a clip runs only the new clip, exactly once")
    func addingRunsOnlyTheNewClip() async {
        let counter = RunCounter()
        let shell = shell(counter)
        let (a, b) = await warmedPair(shell)
        counter.reset()

        let c = shell.addEffect(CountedEffect.descriptor, at: 1000)
        await shell.awaitEvaluation()

        #expect(counter.count(a.id) == 0, "an untouched clip ran \(counter.count(a.id)) times")
        #expect(counter.count(b.id) == 0, "an untouched clip ran \(counter.count(b.id)) times")
        #expect(counter.count(c.id) == 1, "the new clip ran \(counter.count(c.id)) times")
    }

    @Test("adding a clip marks only that clip as catching up")
    func addingSpinsOnlyTheNewClip() async {
        let shell = shell(RunCounter())
        _ = await warmedPair(shell)

        let c = shell.addEffect(CountedEffect.descriptor, at: 1000)

        #expect(shell.evaluatingNodes == [c.id])
        await shell.awaitEvaluation()
    }

    @Test("deleting a clip re-runs nothing")
    func deletingRunsNothing() async {
        let counter = RunCounter()
        let shell = shell(counter)
        let (a, _) = await warmedPair(shell)
        counter.reset()

        shell.removeEffect(a.id)
        await shell.awaitEvaluation()

        #expect(counter.total == 0, "deleting one clip re-ran \(counter.total)")
    }

    @Test("hiding and showing a lane re-runs nothing")
    func toggledLaneRunsNothing() async {
        let counter = RunCounter()
        let shell = shell(counter)
        _ = await warmedPair(shell)
        let lane = try? #require(shell.effects.tracks.first)
        counter.reset()

        shell.toggleVisibility(of: lane!.id)
        await shell.awaitEvaluation()
        shell.toggleVisibility(of: lane!.id)
        await shell.awaitEvaluation()

        #expect(counter.total == 0, "toggling a lane re-ran \(counter.total)")
    }

    /// The other half: what every effect reads still drops every answer, and
    /// each clip runs once for it — the tail rides on the same run.
    @Test("inputsChanged re-runs every clip exactly once")
    func inputsRunEverythingOnce() async {
        let counter = RunCounter()
        let shell = shell(counter)
        let (a, b) = await warmedPair(shell)
        counter.reset()

        shell.inputsChanged()
        await shell.awaitEvaluation()

        #expect(counter.count(a.id) == 1)
        #expect(counter.count(b.id) == 1)
    }

    /// The app assigns the beat twice while a project opens — once when the
    /// window appears and again when the track loads — and each assignment
    /// dropped every clip, scripts included, for a grid that had not changed.
    @Test("assigning the same beat re-runs nothing")
    func sameBeatRunsNothing() async {
        let counter = RunCounter()
        let shell = shell(counter)
        _ = await warmedPair(shell)
        let grid = BeatGrid(timing: OsuParser.parse("[TimingPoints]\n0,500,4,2,0,100,1,0"), divisor: 1)
        shell.beat = grid
        await shell.awaitEvaluation()
        counter.reset()

        shell.beat = BeatGrid(timing: OsuParser.parse("[TimingPoints]\n0,500,4,2,0,100,1,0"), divisor: 1)
        await shell.awaitEvaluation()

        #expect(counter.total == 0, "the same beat re-ran \(counter.total)")
    }

    /// A cancelled pass stops at the next clip instead of running the rest.
    ///
    /// Every edit cancels the pass before it, and opening a project starts
    /// several in a row; a cancelled pass that runs to the end anyway competes
    /// for cores with the one whose result is actually wanted.
    @Test("a cancelled pass evaluates nothing more")
    func cancelledPassStops() async {
        let counter = RunCounter()
        // Cancelled by the first clip it runs: two clips on one lane, so what
        // stops the second is the check between clips, not the one between
        // lanes.
        let evaluator = EffectEvaluator(
            library: EffectLibrary(effects: [CountedEffect(counter: counter, cancelsPass: true)]),
        )
        let cache = EvaluationCache()

        var document = EffectDocument()
        let lane = document.addTrack(layer: .foreground)
        _ = document.add(CountedEffect.descriptor, at: 0, duration: 2000, on: lane.id)
        _ = document.add(CountedEffect.descriptor, at: 3000, duration: 2000, on: lane.id)

        let task = Task.detached {
            _ = cache.sprites(for: document, using: evaluator)
        }
        await task.value

        #expect(counter.total == 1, "a cancelled pass still ran \(counter.total - 1) more clips")
    }
}
