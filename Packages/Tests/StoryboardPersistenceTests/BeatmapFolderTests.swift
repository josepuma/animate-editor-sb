import Foundation
import Testing

@testable import StoryboardPersistence

/// Builds a throwaway folder tree on disk for one test.
private struct TemporaryFolder: ~Copyable {
    let url: URL

    init(files: [String: String]) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("beatmap-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for (relativePath, contents) in files {
            let fileURL = url.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite("BeatmapFolder")
struct BeatmapFolderTests {
    @Test("indexes files recursively")
    func indexesRecursively() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": "[Events]",
            "sb/logo.png": "x",
            "sb/nested/deep.png": "x",
        ])
        let folder = try BeatmapFolder(url: temporary.url)

        #expect(folder.fileCount == 3)
        #expect(folder.fileURL(forRelativePath: "sb/logo.png") != nil)
        #expect(folder.fileURL(forRelativePath: "sb/nested/deep.png") != nil)
    }

    @Test("resolves paths regardless of case")
    func resolvesCaseInsensitively() throws {
        let temporary = try TemporaryFolder(files: ["sb/logo.png": "x"])
        let folder = try BeatmapFolder(url: temporary.url)

        #expect(folder.fileURL(forRelativePath: "SB/LOGO.PNG") != nil)
        #expect(folder.fileURL(forRelativePath: "Sb/Logo.Png") != nil)
    }

    @Test("treats backslashes as separators")
    func resolvesWindowsSeparators() throws {
        let temporary = try TemporaryFolder(files: ["sb/logo.png": "x"])
        let folder = try BeatmapFolder(url: temporary.url)

        // Storyboards authored on Windows write paths this way.
        #expect(folder.fileURL(forRelativePath: #"sb\logo.png"#) != nil)
        #expect(folder.fileURL(forRelativePath: #"SB\LOGO.PNG"#) != nil)
    }

    @Test("missing files resolve to nil")
    func missingFileResolvesToNil() throws {
        let temporary = try TemporaryFolder(files: ["sb/logo.png": "x"])
        let folder = try BeatmapFolder(url: temporary.url)

        #expect(folder.fileURL(forRelativePath: "sb/absent.png") == nil)
        #expect(folder.data(forRelativePath: "sb/absent.png") == nil)
    }

    @Test("path traversal cannot escape the folder")
    func rejectsPathTraversal() throws {
        let temporary = try TemporaryFolder(files: ["sb/logo.png": "x"])
        let folder = try BeatmapFolder(url: temporary.url)

        // `..` segments are dropped, so this resolves inside the folder or not
        // at all — never to a parent directory.
        #expect(folder.fileURL(forRelativePath: "../../../etc/passwd") == nil)
        #expect(folder.fileURL(forRelativePath: "sb/../sb/logo.png") != nil)
    }

    @Test("lists files by extension, case-insensitively")
    func listsByExtension() throws {
        let temporary = try TemporaryFolder(files: [
            "map.osb": "x",
            "easy.osu": "x",
            "hard.OSU": "x",
            "sb/logo.png": "x",
        ])
        let folder = try BeatmapFolder(url: temporary.url)

        #expect(folder.files(withExtensions: ["osb"]) == ["map.osb"])
        #expect(folder.files(withExtensions: ["osu"]).count == 2)
        #expect(folder.files(withExtensions: ["png"]) == ["sb/logo.png"])
    }

    @Test("reads file contents")
    func readsFileContents() throws {
        let temporary = try TemporaryFolder(files: ["sb/notes.txt": "hello"])
        let folder = try BeatmapFolder(url: temporary.url)

        let data = try #require(folder.data(forRelativePath: "sb/notes.txt"))
        #expect(String(data: data, encoding: .utf8) == "hello")
    }

    @Test("a missing folder throws")
    func missingFolderThrows() {
        let url = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString)")
        #expect(throws: BeatmapFolderError.self) {
            try BeatmapFolder(url: url)
        }
    }

    @Test("a file path throws instead of being treated as a folder")
    func filePathThrows() throws {
        let temporary = try TemporaryFolder(files: ["map.osb": "x"])
        #expect(throws: BeatmapFolderError.self) {
            try BeatmapFolder(url: temporary.url.appendingPathComponent("map.osb"))
        }
    }

    @Test("normalise lowercases and resolves relative segments")
    func normaliseBehaviour() {
        #expect(BeatmapFolder.normalise(#"SB\Logo.PNG"#) == "sb/logo.png")
        #expect(BeatmapFolder.normalise("./sb/./logo.png") == "sb/logo.png")
        #expect(BeatmapFolder.normalise("sb//logo.png") == "sb/logo.png")
        #expect(BeatmapFolder.normalise("") == "")

        // `..` pops the preceding segment.
        #expect(BeatmapFolder.normalise("sb/../sb/logo.png") == "sb/logo.png")
        #expect(BeatmapFolder.normalise("a/b/../logo.png") == "a/logo.png")
    }

    @Test("normalise cannot climb above the folder root")
    func normaliseCannotEscapeRoot() {
        // A `..` with nothing to pop is discarded, so the result always stays
        // relative to the beatmap folder.
        #expect(BeatmapFolder.normalise("../secret.png") == "secret.png")
        #expect(BeatmapFolder.normalise("../../../etc/passwd") == "etc/passwd")
        #expect(BeatmapFolder.normalise("sb/../../etc/passwd") == "etc/passwd")
        #expect(!BeatmapFolder.normalise("../../x.png").hasPrefix(".."))
    }
}
