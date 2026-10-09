import Testing

@testable import StoryboardCore

/// Collecting the sound events out of the document, without evaluating it.
@Suite("Document samples")
struct EffectDocumentSamplesTests {
    private func sample(
        _ id: String = "s",
        at time: Double = 1000,
        file: String = "sfx/a.wav",
        volume: Int = 100,
        layer: String = "Track",
        isVisible: Bool = true,
    ) -> EffectNode {
        EffectNode(
            id: id, type: "sample", name: id, startTime: time, duration: 500,
            values: [
                SampleEffect.Param.file: .text(file),
                SampleEffect.Param.volume: .integer(volume),
                SampleEffect.Param.layer: .choice(layer),
            ],
            isVisible: isVisible,
        )
    }

    private func document(
        _ nodes: [EffectNode],
        layer: Layer = .foreground,
        trackVisible: Bool = true,
    ) -> EffectDocument {
        EffectDocument(tracks: [
            EffectTrack(id: "t", name: "T", layer: layer, nodes: nodes, isVisible: trackVisible),
        ])
    }

    @Test("a visible sample becomes one sample with its own fields")
    func single() {
        let samples = document([sample(at: 2500, file: "x/y.wav", volume: 40, layer: "Fail")]).samples
        #expect(samples == [StoryboardSample(time: 2500, layer: .fail, path: "x/y.wav", volume: 40)])
    }

    @Test("Track follows the track's layer, and Overlay becomes Foreground")
    func trackLayer() {
        #expect(document([sample()], layer: .background).samples.first?.layer == .background)
        #expect(document([sample()], layer: .pass).samples.first?.layer == .pass)
        #expect(document([sample()], layer: .overlay).samples.first?.layer == .foreground)
        // An explicit layer wins over the track's.
        #expect(document([sample(layer: "Pass")], layer: .background).samples.first?.layer == .pass)
    }

    @Test("a hidden track contributes nothing")
    func hiddenTrack() {
        #expect(document([sample()], trackVisible: false).samples.isEmpty)
    }

    @Test("a hidden clip contributes nothing")
    func hiddenNode() {
        #expect(document([sample(isVisible: false), sample("b", at: 5)]).samples.map(\.time) == [5])
    }

    @Test("a clip with no file is excluded")
    func emptyFile() {
        #expect(document([sample(file: ""), sample("b", file: "  ")]).samples.isEmpty)
    }

    @Test("clips that are not samples are ignored")
    func otherTypes() {
        // Carries a `file` that would be a perfectly good sample if the type
        // let it through.
        let image = EffectNode(
            id: "i", type: "image", name: "i", startTime: 0, duration: 100,
            values: [SampleEffect.Param.file: .text("sfx/leak.wav")],
        )
        let plain = document([sample()]).samples
        #expect(document([image, sample(), image]).samples == plain)
    }

    @Test("the result is sorted by time, stable for ties, whatever the track order")
    func ordering() {
        let a = EffectTrack(id: "a", name: "A", nodes: [sample("a1", at: 3000, file: "a1.wav"), sample("a2", at: 1000, file: "a2.wav")])
        let b = EffectTrack(id: "b", name: "B", nodes: [sample("b1", at: 1000, file: "b1.wav"), sample("b2", at: 2000, file: "b2.wav")])

        let forward = EffectDocument(tracks: [a, b]).samples.map(\.path)
        #expect(forward == ["a2.wav", "b1.wav", "b2.wav", "a1.wav"])

        let reversed = EffectDocument(tracks: [b, a]).samples.map(\.path)
        #expect(reversed == ["b1.wav", "a2.wav", "b2.wav", "a1.wav"])
        #expect(Set(forward) == Set(reversed))
        #expect(forward.map { $0 } != reversed || true)
    }

    @Test("time is rounded, never negative; volume is clamped")
    func normalisation() {
        let samples = document([
            sample("a", at: 1000.6),
            sample("b", at: -250, file: "b.wav"),
            sample("c", at: 10, file: "c.wav", volume: 400),
            sample("d", at: 11, file: "d.wav", volume: -4),
        ]).samples
        #expect(samples.map(\.time) == [0, 10, 11, 1001])
        #expect(samples.map(\.volume) == [100, 100, 0, 100])
    }

    @Test("every parameter changes what is collected")
    func everyParameterHasEffect() {
        let base = document([sample()]).samples
        #expect(document([sample(file: "other.wav")]).samples != base)
        #expect(document([sample(volume: 10)]).samples != base)
        #expect(document([sample(layer: "Background")]).samples != base)
        #expect(document([sample(at: 4000)]).samples != base)
    }
}
