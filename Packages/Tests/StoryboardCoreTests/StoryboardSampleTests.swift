import Testing

@testable import StoryboardCore

/// Sound samples in the `.osb`: the model, the parser and the writer.
@Suite("Storyboard samples: model, parse, write")
struct StoryboardSampleTests {
    private func parse(_ lines: [String]) -> Storyboard {
        OsbParser.parse((["[Events]"] + lines).joined(separator: "\n") + "\n")
    }

    // ─── Model ───────────────────────────────────────────────────────────────

    @Test("a storyboard has no samples unless it is given some")
    func emptyByDefault() {
        #expect(Storyboard().samples.isEmpty)
        #expect(Storyboard(sprites: [], variables: [:]).samples.isEmpty)
        #expect(OsbParser.parse("[Events]\n").samples.isEmpty)
    }

    // ─── Parse ───────────────────────────────────────────────────────────────

    @Test("a Sample line between two sprites disturbs neither")
    func interleaved() throws {
        let storyboard = parse([
            "Sprite,Foreground,Centre,\"a.png\",320,240",
            " F,0,0,100,0,1",
            "Sample,1000,3,\"sfx/clap.wav\",80",
            "Sprite,Background,Centre,\"b.png\",100,100",
            " F,0,5,10,1,0",
            " S,0,5,10,1,2",
        ])

        #expect(storyboard.sprites.count == 2)
        #expect(storyboard.sprites[0].commands.count == 1)
        #expect(storyboard.sprites[1].commands.count == 2)
        #expect(storyboard.sprites[1].filePath == "b.png")
        let sample = try #require(storyboard.samples.first)
        #expect(storyboard.samples.count == 1)
        #expect(sample == StoryboardSample(time: 1000, layer: .foreground, path: "sfx/clap.wav", volume: 80))
    }

    @Test("a blank or omitted volume is 100")
    func blankVolume() {
        let storyboard = parse([
            "Sample,1000,3,\"a.wav\",",
            "Sample,2000,3,\"b.wav\"",
        ])
        #expect(storyboard.samples.map(\.volume) == [100, 100])
    }

    @Test("a layer is a number or a name")
    func layers() {
        let storyboard = parse([
            "Sample,0,0,\"a.wav\",50",
            "Sample,1,1,\"a.wav\",50",
            "Sample,2,2,\"a.wav\",50",
            "Sample,3,3,\"a.wav\",50",
            "Sample,4,Background,\"a.wav\",50",
            "Sample,5,Fail,\"a.wav\",50",
            "Sample,6,Pass,\"a.wav\",50",
            "Sample,7,Foreground,\"a.wav\",50",
        ])
        #expect(storyboard.samples.map(\.layer) == [
            .background, .fail, .pass, .foreground,
            .background, .fail, .pass, .foreground,
        ])
    }

    @Test("Overlay, out-of-range and junk layers become Foreground, not dropped")
    func oddLayers() {
        let storyboard = parse([
            "Sample,0,Overlay,\"a.wav\",50",
            "Sample,1,4,\"a.wav\",50",
            "Sample,2,-1,\"a.wav\",50",
            "Sample,3,banana,\"a.wav\",50",
            "Sample,4,,\"a.wav\",50",
        ])
        #expect(storyboard.samples.count == 5)
        #expect(storyboard.samples.allSatisfy { $0.layer == .foreground })
    }

    @Test("volume is clamped and a malformed line is skipped without losing the rest")
    func clampAndMalformed() {
        let storyboard = parse([
            "Sample,0,3,\"loud.wav\",250",
            "Sample,1,3,\"quiet.wav\",-5",
            "Sample,x,3,\"no-time.wav\",50",
            "Sample,2,3",
            "Sample,3,3,\"\",50",
            "Sample,4,3,\"ok.wav\",50",
        ])
        #expect(storyboard.samples.map(\.path) == ["loud.wav", "quiet.wav", "ok.wav"])
        #expect(storyboard.samples.map(\.volume) == [100, 0, 50])
    }

    @Test("a fractional time is rounded to a whole millisecond")
    func fractionalTime() {
        let storyboard = parse([
            "Sample,1000.6,3,\"a.wav\",50",
            "Sample,2000.4,3,\"a.wav\",50",
        ])
        #expect(storyboard.samples.map(\.time) == [1001, 2000])
    }

    @Test("an indented line that says Sample is a command, not a sample")
    func indentedIsNotASample() {
        let storyboard = parse([
            "Sprite,Foreground,Centre,\"a.png\",320,240",
            " Sample,1000,3,\"a.wav\",50",
            " F,0,0,100,0,1",
        ])
        #expect(storyboard.samples.isEmpty)
        #expect(storyboard.sprites[0].commands.count == 1)
    }

    // ─── Write ───────────────────────────────────────────────────────────────

    @Test("samples are written under their section, in time order")
    func writesSection() throws {
        let samples = [
            StoryboardSample(time: 3000, layer: .pass, path: "b.wav", volume: 70),
            StoryboardSample(time: 1000, layer: .background, path: "a.wav", volume: 100),
        ]
        let text = OsbWriter.write([], samples: samples)
        let lines = text.split(separator: "\n").map(String.init)

        let header = try #require(lines.firstIndex(of: "//Storyboard Sound Samples"))
        #expect(Array(lines[(header + 1)...]) == [
            "Sample,1000,0,\"a.wav\",100",
            "Sample,3000,2,\"b.wav\",70",
        ])
    }

    @Test("samples with equal times keep the order they were given")
    func stableOrder() {
        let samples = (0..<20).map {
            StoryboardSample(time: 500, layer: .foreground, path: "s\($0).wav", volume: 100)
        }
        let read = OsbParser.parse(OsbWriter.write([], samples: samples)).samples
        #expect(read.map(\.path) == samples.map(\.path))
    }

    @Test("a fractional time and an Overlay layer are written as the format wants them")
    func writerNormalises() {
        // Built by hand, past the parser, which would already have cleaned both.
        let text = OsbWriter.write([], samples: [
            StoryboardSample(time: 1000.6, layer: .overlay, path: "a.wav", volume: 250),
        ])
        #expect(text.contains("\nSample,1001,3,\"a.wav\",100\n"))
    }

    @Test("parse, write, parse gives the same samples")
    func roundTrip() {
        let source = [
            "Sprite,Foreground,Centre,\"a.png\",320,240",
            " F,0,0,100,0,1",
            "Sample,2000.4,Pass,\"sfx/hit.ogg\",",
            "Sprite,Background,Centre,\"b.png\",100,100",
            " F,0,5,10,1,0",
            "Sample,500,0,\"sfx/start.mp3\",35",
            "Sample,900.5,Overlay,\"sfx/o.wav\",90",
        ]
        let first = parse(source)
        let second = OsbParser.parse(OsbWriter.write(first.sprites, samples: first.samples))

        #expect(second.samples == first.samples.sorted { $0.time < $1.time })
        #expect(second.samples.count == 3)
        #expect(second.sprites.count == 2)
        // A blank volume is written explicitly, and Overlay as 3.
        let text = OsbWriter.write(first.sprites, samples: first.samples)
        #expect(text.contains("Sample,2000,2,\"sfx/hit.ogg\",100"))
        #expect(text.contains("Sample,901,3,\"sfx/o.wav\",90"))
    }

    @Test("with no samples the output is exactly what it was before samples existed")
    func byteIdentical() {
        let sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "a.png", defaultX: 1, defaultY: 2,
        )
        let expected = [
            "[Events]",
            "//Background and Video events",
            "//Storyboard Layer 0 (Background)",
            "//Storyboard Layer 1 (Fail)",
            "//Storyboard Layer 2 (Pass)",
            "//Storyboard Layer 3 (Foreground)",
            "Sprite,Foreground,Centre,\"a.png\",1,2",
            "//Storyboard Layer 4 (Overlay)",
            "//Storyboard Sound Samples",
        ].joined(separator: "\n") + "\n"
        #expect(OsbWriter.write([sprite]) == expected)
        #expect(OsbWriter.write([sprite], samples: []) == expected)
    }

    @Test("a path with a quote is not written, since it would corrupt the line")
    func quotePathSkipped() {
        let samples = [
            StoryboardSample(time: 0, layer: .foreground, path: "bad\".wav", volume: 100),
            StoryboardSample(time: 1, layer: .foreground, path: "good.wav", volume: 100),
        ]
        let text = OsbWriter.write([], samples: samples)
        #expect(!text.contains("bad"))
        #expect(OsbParser.parse(text).samples.map(\.path) == ["good.wav"])
    }
}
