import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

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

    // MARK: -

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
