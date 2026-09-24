import Foundation
import Testing

@testable import StoryboardCore

/// Finding the hits in a song: the moments a band's energy jumps.
///
/// Pure over a series of levels, so every case here is built by hand with its
/// hits at known frames — nothing depends on the analyser's stand-in wave,
/// whose smooth sines are exactly what onset detection is meant to ignore.
@Suite("Audio onsets")
struct AudioOnsetsTests {
    private let interval = 50.0

    /// A quiet floor with a hit at each of `frames`: a jump, then a decay —
    /// the shape a kick drum leaves in a band's energy.
    private func hits(at frames: [Int], count: Int = 160, floor: Double = 0.1, peak: Double = 0.9) -> [Double] {
        var series = Array(repeating: floor, count: count)
        for frame in frames {
            for step in 0 ..< 8 where frame + step < count {
                series[frame + step] = max(series[frame + step], floor + (peak - floor) * pow(0.6, Double(step)))
            }
        }
        return series
    }

    @Test("a steady level has no hits")
    func steadyHasNone() {
        #expect(AudioOnsets.detect(Array(repeating: 0.5, count: 200), interval: interval).isEmpty)
    }

    @Test("each hit is found where it lands")
    func findsEachHit() {
        let found = AudioOnsets.detect(hits(at: [20, 60, 100, 140]), interval: interval)
        #expect(found.count == 4, "found \(found)")
        for (time, expected) in zip(found, [1000.0, 3000, 5000, 7000]) {
            #expect(abs(time - expected) <= interval, "a hit at \(time), expected \(expected)")
        }
    }

    /// A slow swell is a crescendo, not a hit. Onsets are about how FAST the
    /// energy rises, so a long ramp to the same peak must not register.
    @Test("a slow swell is not a hit")
    func swellIsNotAHit() {
        let ramp = (0 ..< 200).map { 0.1 + 0.8 * Double($0) / 199 }
        #expect(AudioOnsets.detect(ramp, interval: interval).isEmpty)
    }

    /// A step up that stays up is ONE hit, at the step.
    ///
    /// What separates onset detection from reading the level: the level stays
    /// high for the whole loud stretch, the rise happens once. A version that
    /// thresholded the level itself passed every other case here — its local
    /// threshold hid the difference — and this is the one it cannot.
    @Test("a step up is one hit, at the step")
    func stepIsOneHit() {
        let step = Array(repeating: 0.1, count: 80) + Array(repeating: 0.9, count: 80)
        let found = AudioOnsets.detect(step, interval: interval)
        #expect(found.count == 1, "found \(found)")
        #expect(abs((found.first ?? -1) - 80 * interval) <= interval)
    }

    /// Two hits closer than the gap are one: a flam, or the analyser's window
    /// catching one kick twice. A pulse that fires twice per kick stutters.
    @Test("hits closer than the minimum gap count once")
    func minimumGapMerges() {
        let found = AudioOnsets.detect(hits(at: [40, 42]), interval: interval, minimumGap: 150)
        #expect(found.count == 1, "found \(found)")
    }

    /// Sensitivity decides how small a jump still counts. Higher has to find
    /// at least what lower finds, and the small hits only at the top.
    @Test("sensitivity decides how small a hit still counts")
    func sensitivityIsMonotone() {
        var series = hits(at: [20, 100])
        // Two small hits in between.
        for (frame, bump) in [(60, 0.22), (70, 0.22)] {
            for step in 0 ..< 6 { series[frame + step] = max(series[frame + step], 0.1 + bump * pow(0.6, Double(step))) }
        }
        let low = AudioOnsets.detect(series, interval: interval, sensitivity: 0.1)
        let high = AudioOnsets.detect(series, interval: interval, sensitivity: 0.95)
        #expect(low.count == 2, "low found \(low)")
        #expect(high.count == 4, "high found \(high)")
    }

    /// Loudness is relative to the clip: the same hits over a loud bed have
    /// to be found as they are over a quiet one.
    @Test("hits over a loud bed are found like hits over a quiet one")
    func loudnessIsRelative() {
        // Small enough that the quiet hits fall under the absolute floor unless
        // the series is stretched to its own range first — which is the whole
        // point. A first version used bigger ones and passed without it.
        let quiet = AudioOnsets.detect(hits(at: [30, 90], floor: 0.02, peak: 0.2), interval: interval)
        let loud = AudioOnsets.detect(hits(at: [30, 90], floor: 0.6, peak: 0.95), interval: interval)
        #expect(quiet.count == 2 && loud.count == 2, "quiet \(quiet), loud \(loud)")
    }

    @Test("energy reads the mean of the chosen bands")
    func energyAveragesBands() {
        let frames = AudioSpectrum.Frames(levels: [[0, 1, 1, 0], [1, 1, 0, 0]], interval: interval)
        #expect(AudioOnsets.energy(of: frames, bands: 1 ..< 3) == [1, 0.5])
    }

    /// The demo beat the library previews play to. A preview has no song, and
    /// the stand-in's smooth sines have no hits — so a preset fired by kicks
    /// would sit still in its own picture. The demo has to have kicks the
    /// detector actually finds, about two a second at its 120 BPM.
    @Test("the demo beat has kicks the detector finds")
    func demoBeatKicks() throws {
        let frames = try #require(AudioSpectrum.demoBeat(0 ... 4000, 32, interval))
        let kicks = AudioOnsets.detect(
            AudioOnsets.energy(of: frames, bands: EmitterEffect.AudioBand.bass.bands),
            interval: interval,
        )
        #expect((7 ... 9).contains(kicks.count), "\(kicks.count) kicks in four seconds")
    }
}
