import Foundation
import StoryboardCore
import Testing

@testable import StoryboardRendering

@Suite("Storyboard export")
struct StoryboardExportTests {
    private func sprite(_ path: String, id: String = "s") -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre,
            filePath: path, defaultX: 320, defaultY: 240,
        )
    }

    /// The point of the whole exporter: a file cannot name an image that lives
    /// inside the app, so the path has to become one that exists on disk.
    @Test("a built-in path is written out and repointed")
    func builtInIsGenerated() {
        let result = StoryboardExport.prepare([sprite("__builtin__/glow.png")]) { _ in
            Data([1, 2, 3])
        }

        #expect(result.images.count == 1)
        #expect(!result.storyboard.contains("__builtin__"))
        let written = try? #require(result.images.keys.first)
        if let written { #expect(result.storyboard.contains(written)) }
    }

    /// An emitter points hundreds of particles at one image.
    @Test("one image is written once however many sprites use it")
    func sharedImagesAreWrittenOnce() {
        let sprites = (0..<50).map { sprite("__builtin__/glow.png", id: "s\($0)") }
        let result = StoryboardExport.prepare(sprites) { _ in Data([1]) }

        #expect(result.images.count == 1)
    }

    /// The export folder has to stand on its own: a file naming an image that
    /// is not beside it is a storyboard that only works where it was made.
    @Test("a beatmap's own image is copied, keeping its path")
    func beatmapImagesAreCopiedInPlace() {
        let result = StoryboardExport.prepare([sprite("sb/particle.png")]) { _ in Data([7]) }

        // Copied, so the folder is complete on its own.
        #expect(result.images["sb/particle.png"] != nil)
        // But under the same path, so dropping the folder onto the beatmap
        // lands the file exactly where the storyboard already expects it.
        #expect(result.storyboard.contains("sb/particle.png"))
    }

    /// An image the folder does not have cannot be invented — the sprite keeps
    /// naming it, and the missing file is the mapper's to find.
    @Test("an image that cannot be read is left named as it was")
    func missingImagesAreLeftAlone() {
        let result = StoryboardExport.prepare([sprite("gone.png")]) { _ in nil }

        #expect(result.images.isEmpty)
        #expect(result.storyboard.contains("gone.png"))
    }

    /// A derived path carries its source inside it, separators and all.
    @Test("a derived path becomes a flat file name")
    func derivedNamesAreFlattened() {
        let name = StoryboardExport.fileName(for: "__derived__/blur12/sb/particle.png")

        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".png"))
    }

    @Test("the export lands in its own folder, laid out as it ships")
    func writesToDisk() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let result = StoryboardExport.prepare([sprite("__builtin__/glow.png")]) { _ in Data([9]) }
        let export = try StoryboardExport.write(result, toFolder: folder, named: "Artist - Title")

        #expect(FileManager.default.fileExists(
            atPath: export.appendingPathComponent("Artist - Title.osb").path,
        ))
        for path in result.images.keys {
            #expect(FileManager.default.fileExists(
                atPath: export.appendingPathComponent(path).path,
            ))
        }
    }
}
