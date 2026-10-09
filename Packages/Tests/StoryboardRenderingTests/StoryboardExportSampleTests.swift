import Foundation
import StoryboardCore
import Testing

@testable import StoryboardRendering

@Suite("Storyboard export samples")
struct StoryboardExportSampleTests {
    private func sample(_ path: String, time: Double = 1000, volume: Int = 80) -> StoryboardSample {
        StoryboardSample(time: time, layer: .foreground, path: path, volume: volume)
    }

    private func prepare(
        _ samples: [StoryboardSample],
        audio: @escaping (String) -> Data? = { _ in Data([9, 9]) },
    ) -> StoryboardExport.Result {
        StoryboardExport.prepare([], samples: samples, imageData: { _ in nil }, audioData: audio)
    }

    @Test("a sample writes its line and carries its bytes")
    func lineAndBytes() {
        let result = prepare([sample("sb/clap.wav")]) { _ in Data([1, 2, 3]) }

        #expect(result.storyboard.contains("Sample,1000,3,\"sb/clap.wav\",80"))
        #expect(result.audio["sb/clap.wav"] == Data([1, 2, 3]))
    }

    @Test("the same file used N times is copied once, with N lines")
    func copiedOnce() {
        let result = prepare((0 ..< 4).map { sample("sb/clap.wav", time: Double($0 * 100)) })

        #expect(result.audio.count == 1)
        #expect(result.storyboard.components(separatedBy: "Sample,").count - 1 == 4)
    }

    @Test("an unreadable file keeps its line and copies nothing")
    func unreadable() {
        let result = prepare([sample("sb/gone.wav")]) { _ in nil }

        #expect(result.storyboard.contains("sb/gone.wav"))
        #expect(result.audio.isEmpty)
    }

    @Test("only wav, ogg and mp3 are samples, in any case")
    func extensions() {
        let result = prepare([
            sample("a.WAV"), sample("b.Ogg"), sample("c.mp3"), sample("d.txt"), sample("e.png"), sample("noext"),
        ])

        #expect(Set(result.audio.keys) == ["a.WAV", "b.Ogg", "c.mp3"])
        #expect(!result.storyboard.contains("d.txt"))
        #expect(!result.storyboard.contains("e.png"))
        #expect(!result.storyboard.contains("noext"))
    }

    /// Imported samples are parsed into a `Storyboard` but the export is fed
    /// only the document's samples, as it is only fed the document's sprites.
    @Test("with no samples handed in, no Sample line is written")
    func noSamples() {
        let result = prepare([])
        #expect(!result.storyboard.contains("Sample,"))
        #expect(result.audio.isEmpty)
    }

    @Test("the line and the copy use the same relative path")
    func samePath() throws {
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-sample-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = prepare([sample("sb/clap.wav")]) { _ in Data([5]) }
        let export = try StoryboardExport.write(result, toFolder: sandbox, named: "map")

        #expect(try Data(contentsOf: export.appendingPathComponent("sb/clap.wav")) == Data([5]))
        #expect(result.storyboard.contains("\"sb/clap.wav\""))
    }
}
