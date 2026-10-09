import Foundation
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// The export writes beneath `export/` and nowhere else.
///
/// A sprite or sample path comes from a `.osb` somebody else wrote, so a
/// `..` or an absolute path is input to distrust: written naively it would
/// land outside the folder the export owns — and the export deletes its own
/// folder first, so a path that resolves *to* it is as bad as one that
/// escapes it.
@Suite("Storyboard export containment")
struct StoryboardExportContainmentTests {
    /// A beatmap-like folder inside a throwaway parent, so anything that
    /// escapes lands somewhere the test can look.
    private struct Sandbox {
        let parent: URL
        let folder: URL

        init() throws {
            parent = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("export-containment-\(UUID().uuidString)", isDirectory: true)
            folder = parent.appendingPathComponent("beatmap", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        func exists(_ relativeToParent: String) -> Bool {
            FileManager.default.fileExists(atPath: parent.appendingPathComponent(relativeToParent).path)
        }

        func cleanup() { try? FileManager.default.removeItem(at: parent) }
    }

    private func result(images: [String: Data] = [:], audio: [String: Data] = [:]) -> StoryboardExport.Result {
        StoryboardExport.Result(storyboard: "", images: images, audio: audio)
    }

    @Test("an image path climbing out of export/ is not written")
    func imageEscape() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }

        try StoryboardExport.write(
            result(images: ["../../escape.png": Data([1]), "ok.png": Data([2])]),
            toFolder: sandbox.folder,
            named: "map",
        )

        #expect(!sandbox.exists("escape.png"))
        #expect(!sandbox.exists("beatmap/escape.png"))
        // The rest of the export is not abandoned for one bad path.
        #expect(sandbox.exists("beatmap/export/ok.png"))
    }

    @Test("a sample path with .. or an absolute path is not written")
    func sampleEscape() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        let absolute = sandbox.parent.appendingPathComponent("abs.wav").path

        try StoryboardExport.write(
            result(audio: ["../x.wav": Data([1]), absolute: Data([1])]),
            toFolder: sandbox.folder,
            named: "map",
        )

        #expect(!sandbox.exists("beatmap/x.wav"))
        #expect(!sandbox.exists("abs.wav"))
    }

    @Test("an embedded .. and a sibling-prefix directory are rejected")
    func embeddedAndSibling() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }

        try StoryboardExport.write(
            result(images: [
                "a/../../b.png": Data([1]),
                "../export-evil/x.png": Data([1]),
            ]),
            toFolder: sandbox.folder,
            named: "map",
        )

        #expect(!sandbox.exists("beatmap/b.png"))
        #expect(!sandbox.exists("beatmap/export-evil/x.png"))
    }

    /// `export-evil/` shares `export` as a string prefix. A bare `hasPrefix`
    /// without the trailing slash lets it through.
    @Test("the prefix check is on the directory boundary")
    func boundary() {
        let export = URL(fileURLWithPath: "/tmp/b/export", isDirectory: true)
        #expect(StoryboardExport.contained("../export-evil/x.png", in: export) == nil)
        #expect(StoryboardExport.contained("sub/x.png", in: export) != nil)
    }

    @Test("a backslash cannot smuggle a .. past the check")
    func backslash() {
        let export = URL(fileURLWithPath: "/tmp/b/export", isDirectory: true)
        #expect(StoryboardExport.contained("..\\x.png", in: export) == nil)
        #expect(StoryboardExport.contained("a\\..\\..\\x.png", in: export) == nil)
    }

    @Test("a legitimate nested path is still written")
    func nestedStillWorks() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }

        try StoryboardExport.write(
            result(images: ["sb/_generated/a.png": Data([1])], audio: ["sb/hit.wav": Data([2])]),
            toFolder: sandbox.folder,
            named: "map",
        )

        #expect(sandbox.exists("beatmap/export/sb/_generated/a.png"))
        #expect(sandbox.exists("beatmap/export/sb/hit.wav"))
    }

    @Test("prepare never asks for a file outside the folder")
    func prepareDoesNotRead() {
        var asked: [String] = []
        let sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "../../escape.png", defaultX: 0, defaultY: 0,
        )
        let sample = StoryboardSample(time: 0, layer: .foreground, path: "../x.wav", volume: 100)

        let prepared = StoryboardExport.prepare(
            [sprite], samples: [sample],
            imageData: { asked.append($0); return Data([1]) },
            audioData: { asked.append($0); return Data([1]) },
        )

        #expect(asked.isEmpty)
        #expect(prepared.images.isEmpty)
        #expect(prepared.audio.isEmpty)
        #expect(!prepared.storyboard.contains("Sample,"))
    }
}
