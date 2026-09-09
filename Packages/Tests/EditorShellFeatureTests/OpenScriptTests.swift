import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Handing a script to whatever editor the author uses.
///
/// The launch itself belongs to AppKit, so it arrives through a seam and what
/// is tested here is **which file** gets handed over and **when the offer is
/// made at all** — the two things a wrong answer makes invisible.
@Suite("Open script externally", .serialized)
@MainActor
struct OpenScriptTests {
    /// The clip's own file is what opens.
    @Test("opening a clip hands over its script file")
    func opensTheClipsFile() throws {
        let folder = try temporaryFolder()
        let (shell, nodeID) = try shellWithScript(inFolder: folder, named: "wave")
        let opened = OpenedPaths()
        shell.openScriptHandler = { opened.record($0); return true }

        shell.openScriptExternally(nodeID)

        #expect(opened.all == [folder.appending(path: "wave.js")])
    }

    /// Two clips sharing a file both open the same one.
    ///
    /// The whole point of sharing: whichever clip you reach for, you are
    /// editing the one file.
    @Test("clips sharing a file open the same file")
    func sharedFileOpensOnce() throws {
        let folder = try temporaryFolder()
        let (shell, first) = try shellWithScript(inFolder: folder, named: "shared")
        let second = try #require(shell.duplicateEffect(first)).id
        let opened = OpenedPaths()
        shell.openScriptHandler = { opened.record($0); return true }

        shell.openScriptExternally(first)
        shell.openScriptExternally(second)

        #expect(opened.all.count == 2)
        #expect(Set(opened.all).count == 1, "one file, however many clips name it")
    }

    /// A clip that is not a script has nothing to open.
    @Test("a non-script clip cannot be opened")
    func nonScriptCannotBeOpened() throws {
        let folder = try temporaryFolder()
        let shell = EditorShellModel()
        shell.loadProject(fromFolder: folder)
        let track = shell.addTrack()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, on: track.id)
        let opened = OpenedPaths()
        shell.openScriptHandler = { opened.record($0); return true }

        #expect(!shell.canOpenScript(node.id))
        shell.openScriptExternally(node.id)
        #expect(opened.all.isEmpty)
    }

    /// A file that is not on disk is not offered.
    ///
    /// Handing a missing path to an editor opens an empty untitled window,
    /// which reads as the script having been lost.
    @Test("a missing file is not offered")
    func missingFileIsNotOffered() throws {
        let folder = try temporaryFolder()
        let (shell, nodeID) = try shellWithScript(inFolder: folder, named: "gone")
        try FileManager.default.removeItem(at: folder.appending(path: "gone.js"))

        #expect(!shell.canOpenScript(nodeID))
    }

    /// When nothing can open it, the author is told rather than left guessing.
    @Test("a refused launch is reported")
    func refusedLaunchIsReported() throws {
        let folder = try temporaryFolder()
        let (shell, nodeID) = try shellWithScript(inFolder: folder, named: "wave")
        shell.openScriptHandler = { _ in false }

        shell.openScriptExternally(nodeID)

        #expect(shell.saveError != nil, "a click that does nothing has to say why")
    }

    // MARK: -

    private func shellWithScript(
        inFolder folder: URL,
        named name: String,
    ) throws -> (EditorShellModel, EffectNode.ID) {
        let shell = EditorShellModel()
        shell.loadProject(fromFolder: folder)
        let track = shell.addTrack()
        let node = shell.addEffect(ScriptEffect.descriptor, at: 0, on: track.id)

        // Placed the way a real clip is: a file on disk, named by the node.
        let file = try #require(ScriptFile(name: name))
        try ScriptStore.write("sprite(Image.soft)", to: file, inFolder: folder)
        shell.setScriptFile(file, on: node.id)

        return (shell, node.id)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "open-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// Records the paths handed to the launch seam.
private final class OpenedPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [URL] = []

    func record(_ url: URL) { lock.withLock { paths.append(url) } }
    var all: [URL] { lock.withLock { paths } }
}
