import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// Nothing the timeline or the inspector reads may run an effect on the main
/// thread.
///
/// Reported as "moving or resizing an audio emitter freezes the UI until it
/// finishes, and normal emitters show their spinner instead". The timeline
/// asked every clip how long it plays on every rebuild, and the edit that
/// prompted the rebuild had cleared the answer — so the read evaluated the
/// clip right there, synchronously. A plain emitter costs milliseconds and
/// nobody saw it; an audio emitter has to decode the song under its new
/// position, which is measured in this project at over a second.
///
/// The fourth time this pattern has turned up (`spriteCount`, `tail`, and
/// now `duration(of:on:)`, `passDuration` and `loopSeamSeverity`): a cached
/// answer whose cache is cleared by the very edit that asks for it again is a
/// synchronous evaluation with extra steps. Caught here by listening for the
/// song being read on the main thread, which is exactly the freeze.
@Suite("No evaluation on the main thread", .serialized)
@MainActor
struct MainThreadEvaluationTests {
    /// An analyser that notes every time it is asked from the main thread.
    final class Witness: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var onMain: Int { lock.withLock { calls } }

        var analyser: AudioSpectrum.Analyser {
            { [self] range, bands, interval in
                if Thread.isMainThread { lock.withLock { calls += 1 } }
                let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
                return AudioSpectrum.Frames(
                    levels: (0 ..< count).map { _ in Array(repeating: Float(0.5), count: bands) },
                    interval: interval,
                )
            }
        }
    }

    private func audioEmitter(in shell: EditorShellModel, looped: Bool = false) -> EffectNode {
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 4000)
        shell.setValue(.choice(EmitterEffect.Emission.audio.rawValue), for: EmitterEffect.Param.emission, on: node.id)
        if looped { _ = shell.addFilter(LoopFilter.descriptor, to: node.id) }
        return node
    }

    @Test("the timeline's durations never read the song on the main thread")
    func durationsStayOffMain() async throws {
        let witness = Witness()
        let shell = EditorShellModel()
        shell.audioAnalyser = witness.analyser
        let node = audioEmitter(in: shell)
        _ = await shell.settledSprites()

        // An edit clears the caches, then the timeline asks, as it does on
        // every rebuild.
        shell.setValue(.number(2), for: EmitterEffect.Param.audioContrast, on: node.id)
        _ = shell.duration(of: node.duration, on: node.id)
        _ = shell.passDuration(of: node.id)
        _ = shell.playedTimeRange
        _ = shell.tail(of: node.id)

        #expect(witness.onMain == 0, "the song was read \(witness.onMain)× on the main thread")
        _ = await shell.settledSprites()
    }

    @Test("the loop seam warning never reads the song on the main thread")
    func seamStaysOffMain() async throws {
        let witness = Witness()
        let shell = EditorShellModel()
        shell.audioAnalyser = witness.analyser
        let node = audioEmitter(in: shell, looped: true)
        _ = await shell.settledSprites()

        shell.setValue(.number(3), for: EmitterEffect.Param.audioContrast, on: node.id)
        _ = shell.loopSeamSeverity(for: node.id)

        #expect(witness.onMain == 0, "the song was read \(witness.onMain)× on the main thread")
        _ = await shell.settledSprites()
    }

    /// Off the main thread is only half the promise: the answers still have to
    /// arrive. A tail read from a pass that never lands is a timeline that
    /// stops drawing overhangs.
    @Test("the answers arrive once the pass lands")
    func answersArrive() async throws {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0, duration: 2000)
        shell.setValue(.number(3000), for: EmitterEffect.Param.life, on: node.id)
        _ = await shell.settledSprites()

        #expect(shell.passDuration(of: node.id) > 2000, "a 3s life outlives a 2s clip")
        #expect(shell.duration(of: node.duration, on: node.id) > 2000)
    }
}
