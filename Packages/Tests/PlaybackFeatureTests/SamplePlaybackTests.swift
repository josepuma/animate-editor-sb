import StoryboardCore
import Testing

@testable import PlaybackFeature

/// What the preview hands the sample player as the clock moves. The sink is a
/// recorder: CI has no audio device, and the scheduling is what can be wrong.
@MainActor
@Suite("Sample playback hooks")
struct SamplePlaybackTests {
    private final class Recorder {
        var fired: [(path: String, delay: Double)] = []
        var cancels = 0
    }

    private func sample(_ time: Double, _ path: String = "a.wav") -> StoryboardSample {
        StoryboardSample(time: time, layer: .foreground, path: path, volume: 100)
    }

    private func model(
        samples: [StoryboardSample], range: ClosedRange<Double> = 0...60_000,
    ) -> (PlaybackModel, Recorder) {
        let model = PlaybackModel()
        model.contentLoaded(name: "t", sprites: [], duration: 60_000, audioURL: nil)
        model.loopRange = range
        let recorder = Recorder()
        model.sampleSink = { sample, delay in recorder.fired.append((sample.path, delay)) }
        model.sampleCancel = { recorder.cancels += 1 }
        model.samplesChanged(samples)
        model.seek(to: range.lowerBound)
        recorder.cancels = 0
        return (model, recorder)
    }

    private func run(_ model: PlaybackModel, frames: Int, delta: Double = 16) {
        for _ in 0..<frames { model.advance(by: delta) }
    }

    @Test("a sample fires once while playing, ahead of its moment")
    func firesOnce() {
        let (model, rec) = model(samples: [sample(500)])
        model.startPlayback()
        run(model, frames: 60)
        #expect(rec.fired.count == 1)
        // handed over inside the lookahead, so its start is still in the future
        #expect((rec.fired.first?.delay ?? -1) >= 0)
        #expect((rec.fired.first?.delay ?? 999) <= 100)
    }

    @Test("a sample at the very start sounds when playing from there")
    func atStart() {
        let (model, rec) = model(samples: [sample(0)])
        model.startPlayback()
        run(model, frames: 2)
        #expect(rec.fired.count == 1)
    }

    @Test("a sample before zero fires as the clock crosses it")
    func negative() {
        let (model, rec) = model(samples: [sample(-500)], range: -1000...5000)
        model.startPlayback()
        run(model, frames: 40)
        #expect(rec.fired.count == 1)
    }

    @Test("a sample far past the track's end still fires")
    func afterTrack() {
        let (model, rec) = model(samples: [sample(900_000)], range: 0...2_000_000)
        model.seek(to: 899_900)
        model.startPlayback()
        run(model, frames: 20)
        #expect(rec.fired.count == 1)
    }

    @Test("nothing fires while paused or scrubbing")
    func paused() {
        // 50 is inside the lookahead of a playhead resting at 0
        let (model, rec) = model(samples: [sample(50), sample(500)])
        run(model, frames: 100)
        model.seek(to: 400)
        model.seek(to: 600)
        #expect(rec.fired.isEmpty)
    }

    @Test("a seek while playing skips what lies between, then plays on")
    func seeking() {
        let (model, rec) = model(samples: [sample(1000), sample(5000), sample(9000)])
        model.startPlayback()
        run(model, frames: 2)
        model.seek(to: 8000)
        #expect(rec.cancels >= 1)
        run(model, frames: 10)
        #expect(rec.fired.isEmpty)
        run(model, frames: 80)
        #expect(rec.fired.map(\.path) == ["a.wav"])
    }

    @Test("a loop wrap fires nothing for the jump and the start fires again")
    func looping() {
        let (model, rec) = model(samples: [sample(0), sample(900)], range: 0...1000)
        model.startPlayback()
        run(model, frames: 100)
        // two passes' worth of the start sample, one of the other, plus the
        // wrap itself must not have fired the end twice
        let starts = rec.fired.count
        #expect(starts >= 3)
        #expect(rec.fired.count <= 6)
    }

    @Test("pause cuts what is sounding and resuming does not re-fire it")
    func pausing() {
        let (model, rec) = model(samples: [sample(200)])
        model.startPlayback()
        run(model, frames: 20)
        #expect(rec.fired.count == 1)
        model.pause()
        #expect(rec.cancels == 1)
        model.startPlayback()
        run(model, frames: 5)
        #expect(rec.fired.count == 1)
    }

    @Test("pausing exactly on a sample's instant does not sound it again on resume")
    func pausingOnTheInstant() {
        let (model, rec) = model(samples: [sample(160)])
        model.startPlayback()
        run(model, frames: 10)
        #expect(model.currentTime == 160)
        #expect(rec.fired.count == 1)
        model.pause()
        model.startPlayback()
        run(model, frames: 3)
        #expect(rec.fired.count == 1)
    }

    @Test("the delay follows the rate")
    func rate() {
        let (slow, slowRec) = model(samples: [sample(80)])
        slow.rate = 0.5
        slow.startPlayback()
        slow.advance(by: 16)
        let (fast, fastRec) = model(samples: [sample(80)])
        fast.rate = 2
        fast.startPlayback()
        fast.advance(by: 16)
        let s = slowRec.fired.first?.delay ?? 0
        let f = fastRec.fired.first?.delay ?? 0
        #expect(s > f * 3.5)
    }

    @Test("changing the rate while playing re-hands the pending samples over")
    func rateChange() {
        let (model, rec) = model(samples: [sample(60)])
        model.startPlayback()
        model.advance(by: 16)
        #expect(rec.fired.count == 1)
        model.rate = 0.5
        #expect(rec.cancels == 1)
        model.advance(by: 16)
        #expect(rec.fired.count == 2)
        #expect((rec.fired.last?.delay ?? 0) > (rec.fired.first?.delay ?? 0))
    }

    @Test("unloading stops every voice")
    func unload() {
        let (model, rec) = model(samples: [sample(500)])
        model.startPlayback()
        model.unload()
        #expect(rec.cancels >= 1)
    }
}
