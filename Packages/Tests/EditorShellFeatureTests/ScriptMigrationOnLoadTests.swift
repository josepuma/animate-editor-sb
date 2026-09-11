import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore
@testable import StoryboardScripting

/// Opening a project whose scripts still hold their code inline.
///
/// The migration lives on the load path rather than in the decoder because
/// `ProjectFile.decode` is pure and has no folder — and writing the files needs
/// one. This is the guard that says a v1 project actually arrives migrated,
/// which the store's own tests cannot: they never open a project.
@Suite("Script migration on load", .serialized)
@MainActor
struct ScriptMigrationOnLoadTests {
    /// A v1 project's inline code lands in a file, and the clip names it.
    @Test("opening a v1 project migrates its scripts")
    func openingMigrates() throws {
        let folder = try folderWithInlineScript(source: "sprite(Image.soft).fade(0, 10, 0, 1)")
        let shell = EditorShellModel()

        shell.loadProject(fromFolder: folder)

        let node = try #require(shell.effects.tracks.first?.nodes.first)
        let file = try #require(node.scriptFile, "it must name a file after loading")
        #expect(node.needsScriptMigration == false)
        #expect(
            try ScriptStore.read(file, inFolder: folder) == "sprite(Image.soft).fade(0, 10, 0, 1)",
            "the code has to be on disk, not only in memory",
        )
        #expect(!shell.loadFailed)
    }

    /// Migrating is not an edit the author made.
    ///
    /// It happens while opening, so claiming unsaved changes would ask someone
    /// to save a project they have not touched — and offering undo would step
    /// back into a document whose files no longer match.
    @Test("migrating does not dirty the project or fill the undo stack")
    func migrationIsNotAnEdit() throws {
        let folder = try folderWithInlineScript(source: "sprite(Image.glow)")
        let shell = EditorShellModel()

        shell.loadProject(fromFolder: folder)

        #expect(!shell.hasUnsavedChanges, "opening a project is not changing it")
        #expect(!shell.canUndo, "there is nothing here the author did")
    }

    /// A folder that cannot be written leaves the project openable.
    ///
    /// The code is still in the `.aesb`, so the clip keeps working from its
    /// resolved source. Refusing to open would lose the whole project over a
    /// permission on one file.
    @Test("a project whose scripts cannot be written still opens")
    func unwritableFolderStillOpens() throws {
        let folder = try folderWithInlineScript(source: "sprite(Image.soft)")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: folder.path,
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: folder.path,
            )
        }
        let shell = EditorShellModel()

        shell.loadProject(fromFolder: folder)

        #expect(!shell.loadFailed, "a project is not lost because a script file could not be written")
        #expect(shell.effects.tracks.first?.nodes.first?.scriptSource == "sprite(Image.soft)")
    }

    /// Opening a project with a script leaves the editor's types beside it.
    ///
    /// Both files, because measured they only work together: with the `.d.ts`
    /// alone the declarations are silently ignored while completion still
    /// appears to work, offering identifiers scraped from the file's own text.
    @Test("opening a project writes the type declarations")
    func loadWritesTypeDeclarations() throws {
        let folder = try folderWithInlineScript(source: "sprite(Image.soft)")
        let shell = EditorShellModel()
        shell.writeScriptTypesHandler = writeTypes

        shell.loadProject(fromFolder: folder)

        let declarations = folder.appending(path: TypeDeclarations.fileName)
        let config = folder.appending(path: TypeDeclarations.configurationFileName)
        #expect(FileManager.default.fileExists(atPath: declarations.path))
        #expect(FileManager.default.fileExists(atPath: config.path))
        #expect(
            try String(contentsOf: declarations, encoding: .utf8) == TypeDeclarations.text,
            "what is on disk has to be what the generator produces",
        )
    }

    /// A project with no scripts gets no generated files.
    ///
    /// They are for an external editor to read, so a folder nobody will open
    /// in one does not need them — and two files nothing references would land
    /// in the mapper's published beatmap folder for nothing.
    @Test("a project without scripts is left clean")
    func noScriptsNoFiles() throws {
        let folder = try folderWithoutScripts()
        let shell = EditorShellModel()
        shell.writeScriptTypesHandler = writeTypes

        shell.loadProject(fromFolder: folder)

        #expect(!FileManager.default.fileExists(
            atPath: folder.appending(path: TypeDeclarations.fileName).path,
        ))
    }

    /// Opening a second project stops watching the first.
    ///
    /// Left running, the old watcher reloads **this** project every time
    /// someone edits a script in the beatmap folder they just closed — and the
    /// reload would be silent, because nothing about it looks like a bug from
    /// the outside.
    @Test("opening another project stops the previous watcher")
    func openingAnotherProjectStopsTheWatcher() throws {
        let first = try folderWithInlineScript(source: "sprite(Image.soft)")
        let second = try folderWithInlineScript(source: "sprite(Image.glow)")
        let stops = StopCounter()

        let shell = EditorShellModel()
        shell.writeScriptTypesHandler = writeTypes
        shell.watchScriptsHandler = { _, _ in { stops.record() } }

        shell.loadProject(fromFolder: first)
        #expect(stops.count == 0, "nothing to stop yet")

        shell.loadProject(fromFolder: second)

        #expect(stops.count == 1, "the first project's watcher has to be stopped")
    }

    /// A handler installed after the project loaded still gets used.
    ///
    /// This is the bug the app actually had: `loadProject` runs early in
    /// `.onAppear` and the handlers were installed a couple of hundred lines
    /// further down the same block, so `watchScriptsHandler` was still `nil`
    /// when the load consulted it. The watcher was never installed — for an
    /// hour, while every test passed, because every test installs its handlers
    /// first.
    ///
    /// Ordering is a real constraint for a caller and an unreasonable one to
    /// impose: a model that only works when its seams are filled in the right
    /// order fails silently the moment someone moves a line.
    @Test("a watcher installed after loading still starts")
    func handlerInstalledAfterLoadStillStarts() throws {
        let folder = try folderWithInlineScript(source: "sprite(Image.soft)")
        let shell = EditorShellModel()
        shell.writeScriptTypesHandler = writeTypes

        // Loaded *before* the watcher is installed, which is the app's order.
        shell.loadProject(fromFolder: folder)

        let started = StopCounter()
        shell.watchScriptsHandler = { _, _ in { started.record() } }

        #expect(shell.isWatchingScripts, "installing a watcher on an open project has to start it")
    }

    /// And the ordinary order still works.
    @Test("a watcher installed before loading starts too")
    func handlerInstalledBeforeLoadStarts() throws {
        let folder = try folderWithInlineScript(source: "sprite(Image.soft)")
        let shell = EditorShellModel()
        shell.writeScriptTypesHandler = writeTypes
        shell.watchScriptsHandler = { _, _ in {} }

        shell.loadProject(fromFolder: folder)

        #expect(shell.isWatchingScripts)
    }

    // MARK: -

    /// What the app installs: the generator, writing into the folder.
    private func writeTypes(_ folder: URL) throws {
        try TypeDeclarations.text.write(
            to: folder.appending(path: TypeDeclarations.fileName),
            atomically: true,
            encoding: .utf8,
        )
        try TypeDeclarations.configuration.write(
            to: folder.appending(path: TypeDeclarations.configurationFileName),
            atomically: true,
            encoding: .utf8,
        )
    }

    private func folderWithoutScripts() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "no-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        _ = document.add(EmitterEffect.descriptor, at: 0, duration: 4000, on: track.id)
        try ProjectFile.write(Project(document: document), toFolder: folder)
        return folder
    }

    private func folderWithInlineScript(source: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "migrate-on-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        var node = document.add(ScriptEffect.descriptor, at: 0, duration: 4000, on: track.id)
        node.scriptSource = source
        node.scriptFile = nil
        document[node.id] = node

        try ProjectFile.write(Project(document: document), toFolder: folder)
        return folder
    }
}

/// Counts how many times a watcher was stopped.
private final class StopCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stops = 0

    func record() { lock.withLock { stops += 1 } }
    var count: Int { lock.withLock { stops } }
}
