import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardPersistence

/// Noticing that a script changed on disk.
///
/// The policy is tested here; the FSEvents registration that feeds it is a
/// thin wrapper left untested, because a real stream needs a run loop and this
/// project already carries three suites CI cannot run.

/// Collects what the coalescer reported, across the actor hop.
///
/// The callback is `@Sendable`, so a captured `var` does not compile — and it
/// should not: the report arrives on whatever context the coalescer's timer
/// resumes on.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[ScriptFile]] = []

    func record(_ scripts: [ScriptFile]) {
        lock.withLock { batches.append(scripts) }
    }

    var count: Int { lock.withLock { batches.count } }
    var latest: [ScriptFile] { lock.withLock { batches.last ?? [] } }
}

@Suite("Script folder watcher")
struct ScriptFolderWatcherTests {
    /// A save reports the file that changed.
    @Test("a changed script is reported")
    func changedScriptIsReported() async {
        let coalescer = ScriptChangeCoalescer(interval: 0)
        let reports = Reports()

        await coalescer.handle(["wave.js"]) { reports.record($0) }

        #expect(reports.latest == [ScriptFile(name: "wave")!])
    }

    /// The two events an atomic save produces are one reload.
    ///
    /// Measured with a real FSEvents stream: a temp-write-and-rename — which
    /// is how editors save — produces `renamed` **twice** on the same path. Not
    /// coalesced, every save would evaluate the document twice.
    @Test("an atomic save's two events are one reload")
    func atomicSaveCoalesces() async {
        let coalescer = ScriptChangeCoalescer(interval: 0.08)
        let reports = Reports()

        // Two saves inside one window, naming different files.
        //
        // What this pins is the **outcome**: a burst is one reload that names
        // every script it touched. It deliberately does not claim to pin the
        // cancel — measured, removing that still gives one reload, because the
        // pending set and `flush`'s empty check are what coalesce. Asserting
        // otherwise would be a guard that cannot fail.
        await coalescer.handle(["wave.js"]) { reports.record($0) }
        try? await Task.sleep(for: .milliseconds(20))
        await coalescer.handle(["aurora.js"]) { reports.record($0) }
        try? await Task.sleep(for: .milliseconds(300))

        #expect(reports.count == 1, "a burst is one reload, not one per event")
        #expect(
            Set(reports.latest) == Set([ScriptFile(name: "wave")!, ScriptFile(name: "aurora")!]),
            "and it names every script the burst touched",
        )
    }

    /// The editor's own temporary files are not scripts.
    ///
    /// Measured: the temp half of an atomic save arrives under **its own
    /// name** — `.script.js.tmp.12345`, `script.js.sb-abcdef`. Acting on those
    /// means trying to read a file that no longer exists.
    /// Each name below is refused by a **different** guard, on purpose.
    ///
    /// The first version listed only names that fail the `.js` check, so
    /// deleting the hidden-file guard changed nothing and the test still
    /// passed. `.wave.js` is the one that needs it — an editor's dotfile
    /// that does end in `.js`.
    @Test("temporary files are ignored", arguments: [
        ".wave.js",
        ".wave.js.tmp.12345",
        "wave.js.sb-abcdef",
        ".wave.js.saving",
        "wave.txt",
        "storyboard.aesb",
        "animate.d.ts",
        "types.d.js",
    ])
    func temporaryFilesAreIgnored(_ name: String) async {
        let coalescer = ScriptChangeCoalescer(interval: 0)
        let reports = Reports()

        await coalescer.handle([name]) { reports.record($0) }

        #expect(reports.count == 0, "\(name) is not a script the author edits")
    }

    /// A `.d.ts` is written by us, so reacting to it would be a loop.
    @Test("the generated declarations do not trigger a reload")
    func generatedFilesDoNotLoop() async {
        let coalescer = ScriptChangeCoalescer(interval: 0)
        let reports = Reports()

        await coalescer.handle([ScriptStore.declarationsFileName]) { reports.record($0) }

        #expect(reports.count == 0)
    }

    /// Several files changing at once is one reload naming all of them.
    @Test("a batch reports every script once")
    func batchReportsEachOnce() async {
        let coalescer = ScriptChangeCoalescer(interval: 0)
        let reports = Reports()

        await coalescer.handle(["a.js", "b.js", "a.js"]) { reports.record($0) }

        #expect(Set(reports.latest) == Set([ScriptFile(name: "a")!, ScriptFile(name: "b")!]))
        #expect(reports.latest.count == 2, "one file named twice in a batch is one script")
    }

    /// Nothing to report is not a reload.
    @Test("an irrelevant batch does not fire at all")
    func irrelevantBatchDoesNotFire() async {
        let coalescer = ScriptChangeCoalescer(interval: 0)
        let reports = Reports()

        await coalescer.handle(["audio.mp3", "background.jpg"]) { reports.record($0) }

        #expect(reports.count == 0, "a reload that reloads nothing still costs an evaluation")
    }
}
