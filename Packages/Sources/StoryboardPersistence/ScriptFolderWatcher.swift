import Foundation
import StoryboardCore

/// Turns a burst of filesystem events into one reload naming the scripts.
///
/// Separate from the FSEvents stream so the policy can be tested without one:
/// a real stream needs a run loop, and this project already carries three
/// suites CI cannot run. The stream is the thin part; the deciding is here.
public actor ScriptChangeCoalescer {
    /// How long to wait for a burst to finish.
    private let interval: Duration
    private var pending: Set<ScriptFile> = []
    private var scheduled: Task<Void, Never>?

    public init(interval: TimeInterval) {
        self.interval = .milliseconds(Int(interval * 1000))
    }

    /// Accepts a batch of changed paths, reporting the scripts among them.
    ///
    /// Coalesced because an atomic save is **two** events, measured with a real
    /// stream: an editor writes a temporary file and renames it over the
    /// target, and the rename reports the destination twice. Acting on each
    /// would evaluate the whole document twice per save.
    public func handle(
        _ names: [String],
        report: @escaping @Sendable ([ScriptFile]) -> Void,
    ) {
        let scripts = names.compactMap(Self.script(named:))
        guard !scripts.isEmpty else {
            // A batch with no script in it is not a reload. Firing anyway
            // costs a full evaluation to redraw exactly what is on screen —
            // and a folder holds audio, images and the project file, all of
            // which change for reasons a script does not care about.
            return
        }

        pending.formUnion(scripts)

        // No window asked for means report now, on this call.
        //
        // Not a shortcut for tests: a caller that wants every event is a
        // caller with nothing to coalesce, and going through a zero-length
        // sleep makes the report land whenever the scheduler gets to it. A
        // test written against that passes alone and fails under load, which
        // is a guard that reports on machine speed rather than on behaviour —
        // measured, two of these went red only in the full suite.
        guard interval > .zero else {
            flush(report)
            return
        }

        // What actually coalesces is the pending set plus the empty check in
        // `flush`: the first flush drains it, so a task left over from an
        // earlier event finds nothing and stays quiet. Measured — removing the
        // cancel below still gives one reload for a burst.
        //
        // The cancel is here so the window slides with the burst rather than
        // firing mid-way through it: without it, a long burst reports its
        // first few files, then the rest, which is two evaluations for one
        // save.
        scheduled?.cancel()
        scheduled = Task { [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self.flush(report)
        }
    }

    private func flush(_ report: @escaping @Sendable ([ScriptFile]) -> Void) {
        guard !pending.isEmpty else { return }
        let scripts = Array(pending)
        pending.removeAll()
        report(scripts)
    }

    /// The script a changed path names, or `nil` when it names something else.
    ///
    /// Rejects the editor's own temporaries, which arrive under their **own**
    /// names — measured: `.script.js.tmp.12345` and `script.js.sb-abcdef` each
    /// produce their own event. Reading one means reading a file that has
    /// already been renamed away. It also rejects the files this app generates,
    /// because reacting to our own write on project open is a loop.
    static func script(named name: String) -> ScriptFile? {
        guard name.hasSuffix(".js") else { return nil }
        guard !ScriptStore.generatedFileNames.contains(name) else { return nil }
        // A declarations file spelled `.d.js` is still ours, not the author's.
        guard !name.hasSuffix(".d.js") else { return nil }

        // Dotfiles need no guard here: `ScriptFile` refuses a leading dot, so
        // `.wave.js.saving` — an editor's own temporary — comes back `nil` from
        // the type itself. A second check would read as defence while being
        // unable to fail on its own, which is worse than none: a mutation
        // deleting it changes nothing, so nothing can tell you it mattered.
        return ScriptFile(name: name)
    }
}
