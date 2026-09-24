import Foundation
import Testing

@testable import StoryboardCore

/// The emitter listening to the song: births that follow the music, a
/// spectrum shape that emits from each band, and particles that react to how
/// loud it was when they were born.
///
/// No analyser is installed, so these run against `AudioSpectrum`'s
/// deterministic stand-in — the same one a project with no song gets. Nothing
/// here installs one either: the analyser is a global, and swapping a global
/// under parallel suites is the race `ScriptRuntime` already paid for.
///
/// Every check measures the SPRITES against the RAW levels. None of them
/// re-derives the emitter's weighting: a test that repeats its subject's
/// formula agrees with any formula.
@Suite("Audio emitter")
struct AudioEmitterTests {
    private let evaluator = EffectEvaluator()
    private let duration = 6000.0

    /// What the emitter analyses: 32 bands every 50ms. Named here so the test
    /// asks for the same frames, not so it can repeat the maths.
    private let bands = 32
    private let interval = 50.0

    private func sprites(_ overrides: [String: EffectValue]) -> [StoryboardSprite] {
        var values = EmitterEffect.descriptor.defaultValues
        values[EmitterEffect.Param.count] = .integer(600)
        values[EmitterEffect.Param.gravity] = .number(0)
        values[EmitterEffect.Param.drag] = .number(0)
        values[EmitterEffect.Param.velocityRandom] = .number(0)
        for (key, value) in overrides { values[key] = value }
        return evaluator.evaluate(EffectNode(
            id: "fx", type: "emitter", name: "Emitter",
            startTime: 0, duration: duration, seed: 5, values: values,
        ))
    }

    private var frames: AudioSpectrum.Frames {
        AudioSpectrum.levels(in: 0 ... duration, bands: bands, interval: interval, using: nil)
    }

    /// The mean raw level of some bands, frame by frame.
    private func energy(_ range: Range<Int>) -> [Double] {
        frames.levels.map { frame in
            range.reduce(0.0) { $0 + Double(frame[$1]) } / Double(range.count)
        }
    }

    private func birth(_ sprite: StoryboardSprite) -> Double {
        sprite.commands.map(\.timing.startTime).min() ?? 0
    }

    private func frame(at time: Double, of count: Int) -> Int {
        min(count - 1, max(0, Int(time / interval)))
    }

    /// Straight-line speed, px per ms — gravity and drag are off, so one move.
    private func speed(_ sprite: StoryboardSprite) -> Double? {
        for command in sprite.commands {
            if case let .move(sx, sy, ex, ey) = command.payload {
                let span = command.timing.endTime - command.timing.startTime
                guard span > 0 else { return nil }
                return hypot(ex - sx, ey - sy) / span
            }
        }
        return nil
    }

    // ─── Emission: Audio ─────────────────────────────────────────────────────

    /// The point of it: particles come when the song is loud. Uniform births
    /// would put half of them in the louder half of the frames; following the
    /// music has to put clearly more there.
    @Test("births crowd where the song is loud", arguments: EmitterEffect.AudioBand.allCases)
    func birthsFollowTheMusic(band: EmitterEffect.AudioBand) {
        let drawn = sprites([
            EmitterEffect.Param.emission: .choice("Audio"),
            EmitterEffect.Param.audioBand: .choice(band.rawValue),
        ])
        #expect(drawn.count == 600, "the count is a total, not a rate")

        let levels = energy(band.bands)
        let median = levels.sorted()[levels.count / 2]
        let loud = drawn.filter { levels[frame(at: birth($0), of: levels.count)] > median }.count

        #expect(Double(loud) > Double(drawn.count) * 0.7,
                "\(band.rawValue): \(loud) of \(drawn.count) born in the louder half")
    }

    /// Contrast is what makes a hit stand out from a hum. More of it has to
    /// push MORE of the births into the loud frames.
    @Test("contrast sharpens how much the births follow the hits")
    func contrastSharpens() {
        let levels = energy(EmitterEffect.AudioBand.all.bands)
        let top = levels.sorted()[levels.count * 3 / 4]
        func share(_ contrast: Double) -> Double {
            let drawn = sprites([
                EmitterEffect.Param.emission: .choice("Audio"),
                EmitterEffect.Param.audioContrast: .number(contrast),
            ])
            let loud = drawn.filter { levels[frame(at: birth($0), of: levels.count)] > top }.count
            return Double(loud) / Double(drawn.count)
        }
        #expect(share(5) > share(1) + 0.1, "contrast 5: \(share(5)), contrast 1: \(share(1))")
    }

    // ─── Shape: Spectrum ─────────────────────────────────────────────────────

    /// Bass on the left, treble on the right, each column emitting by its own
    /// level AT THAT MOMENT.
    ///
    /// Measured per birth, not summed over the clip. The first version of this
    /// asked whether the loudest column threw more than the quietest overall —
    /// and passed with columns dealt round-robin, ignoring the song entirely:
    /// the stand-in has every band use its whole range over time, so summed
    /// up, every column is about as loud as every other. What a spectrum has to
    /// do is fire from the band that is loud *now*.
    @Test("a spectrum fires from the bands that are loud at that moment")
    func spectrumFollowsBands() {
        let columns = 16
        let width = 640.0
        let drawn = sprites([
            EmitterEffect.Param.shape: .choice("Spectrum"),
            EmitterEffect.Param.emission: .choice("Audio"),
            EmitterEffect.Param.spectrumBands: .integer(columns),
            EmitterEffect.Param.width: .number(width),
            EmitterEffect.Param.height: .number(4),
        ])
        #expect(drawn.count > 100)

        let left = 320 - width / 2
        let perColumn = bands / columns
        let grid = (0 ..< columns).map { column in
            energy(column * perColumn ..< (column + 1) * perColumn)
        }

        var louder = 0
        for sprite in drawn {
            #expect(sprite.defaultX >= left - 0.5 && sprite.defaultX <= left + width + 0.5)
            let column = min(columns - 1, max(0, Int((sprite.defaultX - left) / (width / Double(columns)))))
            let at = frame(at: birth(sprite), of: grid[0].count)
            let row = grid.map { $0[at] }.sorted()
            if grid[column][at] > row[columns / 2] { louder += 1 }
        }
        #expect(Double(louder) > Double(drawn.count) * 0.7,
                "\(louder) of \(drawn.count) fired from a louder-than-median band")
    }

    // ─── Reactivity ──────────────────────────────────────────────────────────

    private func speedsByLevel(reactivity: Double) -> (loud: Double, quiet: Double) {
        let drawn = sprites([EmitterEffect.Param.audioReactivity: .number(reactivity)])
        let levels = energy(EmitterEffect.AudioBand.all.bands)
        let sorted = levels.sorted()
        let high = sorted[sorted.count * 3 / 4], low = sorted[sorted.count / 4]

        var loud: [Double] = [], quiet: [Double] = []
        for sprite in drawn {
            guard let v = speed(sprite) else { continue }
            let level = levels[frame(at: birth(sprite), of: levels.count)]
            if level >= high { loud.append(v) } else if level <= low { quiet.append(v) }
        }
        func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(max(1, xs.count)) }
        return (mean(loud), mean(quiet))
    }

    @Test("reactive particles born on a hit fly faster")
    func reactivityScalesSpeed() {
        let (loud, quiet) = speedsByLevel(reactivity: 1.5)
        #expect(loud > quiet * 1.3, "loud \(loud), quiet \(quiet)")
    }

    /// Reactivity lands on presets that already exist, so at its default it
    /// must change nothing: without randomness every particle keeps one speed.
    @Test("reactivity at zero leaves every speed alone")
    func reactivityIsInert() {
        let (loud, quiet) = speedsByLevel(reactivity: 0)
        #expect(abs(loud - quiet) < 1e-9, "loud \(loud), quiet \(quiet)")
    }
}
