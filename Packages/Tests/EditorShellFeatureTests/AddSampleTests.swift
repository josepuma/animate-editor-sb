import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Placing a sound on the timeline.
///
/// The subject is built the way the app builds it: a bare shell, with the
/// length-of-file seam installed or not.
@MainActor
@Suite("Add sample")
struct AddSampleTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test("the clip is as long as the file and starts at the given time")
    func durationFromSeam() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in 2.5 }

        let node = try #require(shell.addSample(at: "sb/clap.wav", time: 1200))

        #expect(node.duration == 2500)
        #expect(node.startTime == 1200)
        #expect(node.type == SampleEffect.descriptor.type)
        #expect(shell.effects[node.id]?.values[SampleEffect.Param.file] == .text("sb/clap.wav"))
    }

    @Test("an unreadable file still places, with the fallback length")
    func seamReturnsNil() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in nil }

        let node = try #require(shell.addSample(at: "sb/clap.ogg", time: 0))
        #expect(node.duration == SampleEffect.fallbackDuration)
    }

    @Test("no seam installed also uses the fallback")
    func noSeam() throws {
        let shell = EditorShellModel()
        let node = try #require(shell.addSample(at: "sb/clap.wav", time: 0))
        #expect(node.duration == SampleEffect.fallbackDuration)
    }

    @Test("a zero or negative length from the seam falls back")
    func nonsenseLength() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in 0 }
        let node = try #require(shell.addSample(at: "a.wav", time: 0))
        #expect(node.duration == SampleEffect.fallbackDuration)
    }

    @Test("placing is one undo step and leaves no file-less clip")
    func oneUndoStep() {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in 1 }

        shell.addSample(at: "sb/clap.wav", time: 0)
        #expect(shell.effects.nodes.count == 1)

        shell.undo()
        #expect(shell.effects.nodes.isEmpty)
    }

    @Test("moving a sample never asks for its length again")
    func moveDoesNotRecompute() throws {
        let shell = EditorShellModel()
        let asked = Counter()
        shell.audioDuration = { _ in asked.increment(); return 1 }

        let node = try #require(shell.addSample(at: "sb/clap.wav", time: 0))
        shell.moveEffect(node.id, to: 4000)

        #expect(asked.count == 1)
        #expect(shell.effects[node.id]?.duration == 1000)
        #expect(shell.effects[node.id]?.startTime == 4000)
    }

    @Test("copy, paste and duplicate keep what the sample is, with new ids")
    func copiesKeepTheSample() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in 1.5 }
        let node = try #require(shell.addSample(at: "sb/clap.wav", time: 0))
        shell.setValue(.integer(40), for: SampleEffect.Param.volume, on: node.id)
        shell.setValue(.choice("Pass"), for: SampleEffect.Param.layer, on: node.id)

        shell.selectedNodeID = node.id
        shell.copySelectedEffect()
        let pasted = try #require(shell.pasteEffect(at: 5000))
        let duplicate = try #require(shell.duplicateEffect(node.id))

        for copy in [pasted, duplicate] {
            #expect(copy.id != node.id)
            #expect(copy.type == SampleEffect.descriptor.type)
            #expect(copy.values[SampleEffect.Param.file] == .text("sb/clap.wav"))
            #expect(copy.values[SampleEffect.Param.volume] == .integer(40))
            #expect(copy.values[SampleEffect.Param.layer] == .choice("Pass"))
            #expect(copy.duration == 1500)
        }
        #expect(pasted.id != duplicate.id)
    }

    // ─── Resize ──────────────────────────────────────────────────────────

    @Test("a sample cannot be resized, but can be moved")
    func notResizable() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in 1 }
        let node = try #require(shell.addSample(at: "sb/clap.wav", time: 100))

        shell.resizeEffect(node.id, startTime: 0, duration: 9000)
        #expect(shell.effects[node.id]?.duration == 1000)
        #expect(shell.effects[node.id]?.startTime == 100)

        shell.moveEffect(node.id, to: 700)
        #expect(shell.effects[node.id]?.startTime == 700)
    }

    @Test("the document refuses to resize a sample too")
    func documentNotResizable() throws {
        let shell = EditorShellModel()
        let node = try #require(shell.addSample(at: "sb/clap.wav", time: 100))

        var document = shell.effects
        document.resize(node.id, startTime: 0, duration: 9000)
        #expect(document[node.id]?.duration == SampleEffect.fallbackDuration)
    }

    @Test("an ordinary clip still resizes")
    func ordinaryStillResizes() throws {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "sb/bg.png", time: 0)
        let id = try #require(node?.id)

        shell.resizeEffect(id, startTime: 0, duration: 9000)
        #expect(shell.effects[id]?.duration == 9000)
    }

    // ─── Export ──────────────────────────────────────────────────────────

    @Test("the export receives exactly the document's samples")
    func exportGetsSamples() async throws {
        let shell = EditorShellModel()
        shell.projectFolder = URL(fileURLWithPath: NSTemporaryDirectory())
        shell.addSample(at: "sb/a.wav", time: 300)
        shell.addSample(at: "sb/b.wav", time: 100)

        final class Box: @unchecked Sendable { var samples: [StoryboardSample] = [] }
        let box = Box()
        shell.exportHandler = { _, samples, folder in box.samples = samples; return folder }

        let ok = await shell.exportStoryboard()

        #expect(ok)
        #expect(box.samples == shell.effects.samples)
        #expect(box.samples.map(\.path) == ["sb/b.wav", "sb/a.wav"])
    }
}
