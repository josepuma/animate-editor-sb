import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Getting a script's code off disk and into the node that evaluates it.
///
/// `ScriptEffect.evaluate` is synchronous and cannot throw, so it cannot go to
/// disk — and a seam called from inside it would read a file per node per
/// evaluation, which is the shape that has bitten this project four times.
/// Resolution happens once, on the snapshot, before the detached evaluation.
@Suite("Script resolution", .serialized)
@MainActor
struct ScriptResolutionTests {
    /// A reopened project draws from the file, not from what was saved inline.
    @Test("a clip's source comes from its file")
    func sourceComesFromTheFile() throws {
        let folder = try temporaryFolder()
        let file = try #require(ScriptFile(name: "wave"))
        try ScriptStore.write("sprite(Image.glow)", to: file, inFolder: folder)

        let resolved = ScriptResolver(folder: folder)
            .resolving(document(referencing: file, inlineSource: "sprite(Image.soft)"))

        #expect(
            resolved.nodes.first?.scriptSource == "sprite(Image.glow)",
            "the file is the source of truth, so it wins over anything stored inline",
        )
    }

    /// One file, many clips: every one of them gets the code.
    @Test("every clip sharing a file is resolved")
    func sharedFileReachesEveryClip() throws {
        let folder = try temporaryFolder()
        let file = try #require(ScriptFile(name: "shared"))
        try ScriptStore.write("sprite(Image.soft)", to: file, inFolder: folder)

        var built = EffectDocument()
        let track = built.addTrack(layer: .foreground)
        for _ in 0 ..< 3 {
            var node = built.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
            node.scriptFile = file
            node.scriptSource = nil
            built[node.id] = node
        }

        let resolved = ScriptResolver(folder: folder).resolving(built)

        #expect(resolved.nodes.count == 3)
        #expect(
            resolved.nodes.allSatisfy { $0.scriptSource == "sprite(Image.soft)" },
            "editing one file has to reach every clip that names it",
        )
    }

    /// A missing file leaves the clip with no source, not with stale source.
    ///
    /// Keeping what was there would draw a clip whose file the author deleted —
    /// the silent disagreement between what is on screen and what is on disk
    /// that this whole change exists to end.
    @Test("a missing file clears the source")
    func missingFileClearsSource() throws {
        let folder = try temporaryFolder()
        let file = try #require(ScriptFile(name: "gone"))

        let resolved = ScriptResolver(folder: folder)
            .resolving(document(referencing: file, inlineSource: "sprite(Image.soft)"))

        #expect(resolved.nodes.first?.scriptSource == nil)
    }

    /// A file is read once however many clips name it.
    @Test("a shared file is read once, not once per clip")
    func sharedFileIsReadOnce() throws {
        let folder = try temporaryFolder()
        let file = try #require(ScriptFile(name: "counted"))
        try ScriptStore.write("sprite(Image.soft)", to: file, inFolder: folder)

        var built = EffectDocument()
        let track = built.addTrack(layer: .foreground)
        for _ in 0 ..< 5 {
            var node = built.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
            node.scriptFile = file
            built[node.id] = node
        }

        var reads = 0
        let resolver = ScriptResolver(folder: folder) { name, folder in
            reads += 1
            return try? ScriptStore.read(name, inFolder: folder)
        }
        _ = resolver.resolving(built)

        #expect(reads == 1, "five clips naming one file is one read, not five")
    }

    /// A node that is not a script is untouched.
    @Test("a non-script node is left alone")
    func nonScriptUntouched() throws {
        let folder = try temporaryFolder()
        var built = EffectDocument()
        let track = built.addTrack(layer: .foreground)
        let node = built.add(EmitterEffect.descriptor, at: 0, duration: 4000, on: track.id)

        let resolved = ScriptResolver(folder: folder).resolving(built)

        #expect(resolved[node.id]?.scriptSource == nil)
        #expect(resolved[node.id]?.values == built[node.id]?.values)
    }

    /// The whole chain: a v1 project opens, migrates, and reads from disk.
    ///
    /// Every test above resolves a document by hand. This one goes through the
    /// model's own load path, which is the only arrangement that says migration
    /// and resolution are wired to each other — each passing alone has already
    /// proved not to be the same thing.
    ///
    /// It asserts on the resolved document rather than on drawn sprites: the
    /// evaluation is detached and needs the main actor's run loop to deliver
    /// its result, so a synchronous test that blocks waiting for it deadlocks
    /// against the very hop it is waiting on. What this commit adds is the
    /// resolution; `EndToEndTests` already covers a resolved node drawing.
    @Test("a reopened project resolves from the file on disk")
    func reopenedProjectResolvesFromDisk() throws {
        let folder = try temporaryFolder()

        // Saved the way the app saves it, with code still inline.
        var built = EffectDocument()
        let track = built.addTrack(layer: .foreground)
        var node = built.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
        node.scriptSource = "sprite(Image.soft)"
        node.scriptFile = nil
        built[node.id] = node
        try ProjectFile.write(Project(document: built), toFolder: folder)

        let shell = EditorShellModel()
        shell.loadProject(fromFolder: folder)

        // Edited on disk, as an external editor would. Nothing in the document
        // changed, so only a read can pick this up.
        let file = try #require(shell.effects.nodes.first?.scriptFile)
        try ScriptStore.write("sprite(Image.glow)", to: file, inFolder: folder)

        let resolved = ScriptResolver(folder: folder).resolving(shell.effects)

        #expect(
            resolved.nodes.first?.scriptSource == "sprite(Image.glow)",
            "the file on disk decides what runs, not what was saved inline",
        )
    }

    // MARK: -

    private func document(referencing file: ScriptFile, inlineSource: String) -> EffectDocument {
        var built = EffectDocument()
        let track = built.addTrack(layer: .foreground)
        var node = built.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
        node.scriptFile = file
        node.scriptSource = inlineSource
        built[node.id] = node
        return built
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "resolve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
