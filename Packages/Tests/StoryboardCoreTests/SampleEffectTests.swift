import Foundation
import Testing

@testable import StoryboardCore

@Suite("Sample effect")
struct SampleEffectTests {
    private func node(file: String = "sfx/clap.wav") -> EffectNode {
        EffectNode(
            id: "sample-1", type: SampleEffect.descriptor.type, name: "Sample",
            startTime: 1000, duration: 800,
            values: [
                SampleEffect.Param.file: .text(file),
                SampleEffect.Param.volume: .integer(60),
                SampleEffect.Param.layer: .choice("Pass"),
            ],
        )
    }

    @Test("it draws nothing")
    func drawsNothing() {
        let evaluator = EffectEvaluator()
        #expect(evaluator.evaluate(node()).isEmpty)
    }

    @Test("it is registered in the standard library")
    func registered() {
        #expect(EffectLibrary.standard.effect(for: "sample") != nil)
        #expect(EffectLibrary.standard.descriptor(for: "sample")?.name == "Sample")
    }

    @Test("the descriptor says it cannot be resized and draws no sprites; the rest can and do")
    func flags() {
        #expect(SampleEffect.descriptor.isResizable == false)
        #expect(SampleEffect.descriptor.drawsSprites == false)
        for descriptor in EffectLibrary.standard.descriptors where descriptor.type != "sample" {
            #expect(descriptor.isResizable, "\(descriptor.type)")
            #expect(descriptor.drawsSprites, "\(descriptor.type)")
        }
    }

    @Test("a sample survives a save and keeps the format version")
    func roundTrips() throws {
        let track = EffectTrack(id: "t", name: "T", nodes: [node()])
        let project = Project(document: EffectDocument(tracks: [track]))
        let restored = try ProjectFile.decode(try ProjectFile.encode(project))
        let read = try #require(restored.document.nodes.first)

        #expect(read.values[SampleEffect.Param.file] == .text("sfx/clap.wav"))
        #expect(read.values[SampleEffect.Param.volume] == .integer(60))
        #expect(read.values[SampleEffect.Param.layer] == .choice("Pass"))
        #expect(restored.formatVersion == Project.currentVersion)
        #expect(Project.currentVersion == 2)
    }

    @Test("parameters default to no file, full volume, and the track's layer")
    func defaults() {
        let defaults = SampleEffect.descriptor.defaultValues
        #expect(defaults[SampleEffect.Param.file] == .text(""))
        #expect(defaults[SampleEffect.Param.volume] == .integer(100))
        #expect(defaults[SampleEffect.Param.layer] == .choice("Track"))
        #expect(SampleEffect.fallbackDuration == 500)
    }
}
