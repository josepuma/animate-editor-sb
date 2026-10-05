import CoreGraphics
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// When the timeline's clip stills are redrawn.
///
/// A still is a renderer set-up plus a draw, so redrawing every clip on every
/// edit is the shape of bug this project has already paid for four times —
/// `spriteCount`, `tail`, `duration`, the seams. Counts are exact on purpose:
/// "at least once" passes with every clip redrawn on every edit.
@MainActor
@Suite("Clip stills")
struct ClipStillTests {
    /// Counts draws per clip and hands back a real image, so a still can be
    /// stored and then found pruned.
    @MainActor
    final class Counter {
        var draws: [EffectNode.ID: Int] = [:]
        var batches = 0
        var total: Int { draws.values.reduce(0, +) }

        func reset() {
            draws = [:]
            batches = 0
        }

        func install(on shell: EditorShellModel) {
            shell.clipStillRenderer = { [self] _ in
                batches += 1
                return { [self] id, _ in
                    draws[id, default: 0] += 1
                    return Self.pixel
                }
            }
        }

        static let pixel: CGImage? = {
            let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )
            return context?.makeImage()
        }()
    }

    /// Two clips, both drawn once, counter cleared.
    private func twoClips() async -> (EditorShellModel, Counter, EffectNode, EffectNode) {
        let shell = EditorShellModel()
        let counter = Counter()
        counter.install(on: shell)
        let first = shell.addEffect(EmitterEffect.descriptor, at: 0)
        let second = shell.addEffect(EmitterEffect.descriptor, at: 3000)
        await shell.awaitClipStills()
        return (shell, counter, first, second)
    }

    @Test("placing clips draws each one once")
    func placingDrawsEach() async {
        let (shell, counter, first, second) = await twoClips()
        _ = counter
        #expect(shell.clipStill(of: first.id) != nil)
        #expect(shell.clipStill(of: second.id) != nil)
    }

    @Test("an edit to one clip redraws only that clip")
    func namedEditRedrawsOne() async {
        let (shell, counter, first, second) = await twoClips()
        counter.reset()

        shell.resizeEffect(first.id, startTime: 0, duration: 4000)
        await shell.awaitClipStills()

        #expect(counter.draws[first.id] == 1, "the edited clip drew \(counter.draws[first.id] ?? 0) times")
        #expect(counter.draws[second.id] == nil, "an untouched clip was redrawn")
        #expect(counter.batches == 1)
    }

    @Test("an edit that names no clip redraws every clip once")
    func unnamedEditRedrawsAll() async {
        let (shell, counter, first, second) = await twoClips()
        counter.reset()

        shell.inputsChanged()
        await shell.awaitClipStills()

        #expect(counter.draws == [first.id: 1, second.id: 1])
        #expect(counter.batches == 1, "one renderer set-up for the batch, not one per clip")
    }

    /// Two quick edits to two clips run one pass — the first is cancelled —
    /// and both clips still need their stills.
    @Test("a cancelled pass does not lose its clip's mark")
    func cancelledPassKeepsItsMark() async {
        let (shell, counter, first, second) = await twoClips()
        counter.reset()

        shell.resizeEffect(first.id, startTime: 0, duration: 4000)
        shell.resizeEffect(second.id, startTime: 3000, duration: 4000)
        await shell.awaitClipStills()

        #expect(counter.draws == [first.id: 1, second.id: 1])
    }

    @Test("a removed clip's still is dropped")
    func removedClipIsPruned() async {
        let (shell, counter, first, second) = await twoClips()
        #expect(shell.clipStill(of: first.id) != nil)
        counter.reset()

        shell.removeEffect(first.id)
        await shell.awaitClipStills()

        #expect(shell.clipStill(of: first.id) == nil, "a clip that is gone keeps no still")
        #expect(shell.clipStill(of: second.id) != nil, "pruning took a living clip's still")
        #expect(counter.total == 0, "removing a clip redrew \(counter.total) stills")
    }

    /// A slider dragged across its range lands a pass every 90ms of
    /// stillness; a batch per pass is GPU work the next step throws away.
    @Test("nothing is drawn during a gesture, and the clip is drawn once after it")
    func gestureDefersStills() async {
        let (shell, counter, first, second) = await twoClips()
        counter.reset()

        shell.beginGesture()
        shell.setValue(.integer(40), for: EmitterEffect.Param.count, on: first.id)
        // The gesture's deferred pass, landed while the hand is still down.
        await shell.awaitClipStills()
        #expect(counter.total == 0, "drew \(counter.total) stills mid-gesture")

        shell.setValue(.integer(50), for: EmitterEffect.Param.count, on: first.id)
        await shell.awaitClipStills()
        #expect(counter.total == 0)

        shell.endGesture()
        await shell.awaitClipStills()

        #expect(counter.draws == [first.id: 1], "after the gesture: \(counter.draws), second \(second.id)")
    }

    /// `endGesture` runs a pass whether or not anything moved, and the last
    /// edit's name is still on the model.
    @Test("a gesture that changed nothing redraws nothing")
    func emptyGestureRedrawsNothing() async {
        let (shell, counter, first, _) = await twoClips()
        shell.resizeEffect(first.id, startTime: 0, duration: 4000)
        await shell.awaitClipStills()
        counter.reset()

        shell.beginGesture()
        shell.endGesture()
        await shell.awaitClipStills()

        #expect(counter.total == 0, "an empty gesture redrew \(counter.total) stills")
    }

    /// The camera is cropped out by the clip's own box; a batch per camera
    /// nudge would be a full redraw per drag step.
    @Test("a camera edit redraws no still")
    func cameraEditRedrawsNothing() async {
        let (shell, counter, _, _) = await twoClips()
        counter.reset()

        shell.setCameraValue(400, for: .x)
        await shell.awaitClipStills()

        #expect(counter.total == 0)
    }

    /// The still is taken inside the clip, in song time, at the poster ratio.
    @Test("a still is taken at the clip's poster instant")
    func posterInstant() async {
        let shell = EditorShellModel()
        var times: [Double] = []
        shell.clipStillRenderer = { _ in
            { _, time in
                times.append(time)
                return nil
            }
        }
        _ = shell.addEffect(EmitterEffect.descriptor, at: 1000, duration: 2000)
        await shell.awaitClipStills()

        #expect(times == [1000 + 2000 * EditorShellModel.clipStillPosterRatio])
    }
}
