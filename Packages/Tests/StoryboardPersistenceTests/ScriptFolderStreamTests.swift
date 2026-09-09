import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardPersistence

/// The FSEvents stream, against a real folder.
///
/// The thin wrapper the coalescer's tests deliberately leave out — but not
/// untested, because the one thing that could sink this design is FSEvents not
/// naming the final path when an editor saves atomically. That was verified
/// with a standalone probe before any of this was written; this is the guard
/// that keeps it verified.
@Suite("Script folder stream", .serialized)
struct ScriptFolderStreamTests {
    /// A plain write is reported.
    @Test("a direct save is reported")
    func directSaveIsReported() async throws {
        let folder = try temporaryFolder()
        let reports = StreamReports()
        let stream = ScriptFolderStream(folder: folder) { reports.record($0) }
        defer { stream.stop() }

        // FSEvents needs a moment to be listening before the write happens.
        try await Task.sleep(for: .milliseconds(300))
        try "sprite(Image.soft)".write(
            to: folder.appending(path: "wave.js"),
            atomically: false,
            encoding: .utf8,
        )

        let scripts = await reports.wait()
        #expect(scripts.contains(ScriptFile(name: "wave")!))
    }

    /// The shape an editor actually saves with.
    ///
    /// Write a temporary under a different name, rename it over the target.
    /// The measured answer is that the rename reports the **destination** —
    /// which is what makes watching the folder work at all, and what makes
    /// holding a descriptor on the file useless.
    @Test("an atomic save names the final file")
    func atomicSaveNamesTheFinalFile() async throws {
        let folder = try temporaryFolder()
        let target = folder.appending(path: "aurora.js")
        try "sprite(Image.soft)".write(to: target, atomically: false, encoding: .utf8)

        let reports = StreamReports()
        let stream = ScriptFolderStream(folder: folder) { reports.record($0) }
        defer { stream.stop() }
        try await Task.sleep(for: .milliseconds(300))

        let temporary = folder.appending(path: ".aurora.js.tmp.12345")
        try "sprite(Image.glow)".write(to: temporary, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)

        let scripts = await reports.wait()
        #expect(
            scripts.contains(ScriptFile(name: "aurora")!),
            "a rename has to report its destination, or watching the folder cannot work",
        )
        #expect(
            !scripts.contains(where: { $0.name.contains("tmp") }),
            "and the temporary half is not a script",
        )
    }

    /// Stopping means no more reports.
    @Test("a stopped stream goes quiet")
    func stoppedStreamGoesQuiet() async throws {
        let folder = try temporaryFolder()
        let reports = StreamReports()
        let stream = ScriptFolderStream(folder: folder) { reports.record($0) }
        try await Task.sleep(for: .milliseconds(300))
        stream.stop()

        try "sprite(Image.soft)".write(
            to: folder.appending(path: "after.js"),
            atomically: false,
            encoding: .utf8,
        )
        try await Task.sleep(for: .milliseconds(500))

        #expect(reports.all.isEmpty, "a stopped stream must not keep reloading")
    }

    // MARK: -

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "stream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// Collects reports arriving from the stream's queue.
private final class StreamReports: @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: Set<ScriptFile> = []

    func record(_ batch: [ScriptFile]) {
        lock.withLock { scripts.formUnion(batch) }
    }

    var all: Set<ScriptFile> { lock.withLock { scripts } }

    /// Waits for something to arrive, up to a generous bound.
    ///
    /// Generous on purpose: the claim is that an event arrives at all, and a
    /// tight bound turns a loaded machine into a red test — which teaches
    /// people to ignore red tests.
    func wait() async -> Set<ScriptFile> {
        for _ in 0 ..< 60 {
            if !all.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return all
    }
}
