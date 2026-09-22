import Foundation
import Testing
@testable import StoryboardCore
@testable import StoryboardScripting

/// A script can read the song under its own clip.
///
/// The one thing a script legitimately needs from outside that cannot be handed
/// to it as a number. What makes it delicate is the rule it must not break:
/// a script is never told where its clip sits, because one that could name a
/// moment of the song would draw *different* particles when dragged — and a
/// clip being safe to move is what the whole timeline rests on.
@Suite("Script audio bridge", .serialized)
struct AudioBridgeTests {
    /// Levels where band `b` of frame `f` is a value only that pair produces,
    /// so a reading landing on the wrong one is visible rather than plausible.
    private func frames(count: Int, bands: Int, interval: Double) -> AudioSpectrum.Frames {
        AudioSpectrum.Frames(
            levels: (0 ..< count).map { f in
                (0 ..< bands).map { b in Float(f) / 100 + Float(b) / 1000 }
            },
            interval: interval,
        )
    }

    private func run(_ source: String, spectrum: AudioSpectrum.Frames?) -> ScriptRuntime.Outcome {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "n", idPrefix: "n", source: source, values: [:],
            duration: 1000, seed: 1, spectrum: spectrum,
        ))
    }

    /// The values reach the script, and from the right frame.
    @Test("a script reads the levels it was handed")
    func readsLevels() {
        let spectrum = frames(count: 10, bands: 4, interval: 100)
        let outcome = run("""
        // Frame 3 is 300ms in; band 2 of it is 3/100 + 2/1000 = 0.032.
        const got = audio.level(300, 2)
        if (Math.abs(got - 0.032) > 1e-6) { throw new Error('band read ' + got) }
        if (audio.bands !== 4) { throw new Error('bands ' + audio.bands) }
        if (audio.interval !== 100) { throw new Error('interval ' + audio.interval) }
        if (!audio.isReal) { throw new Error('isReal false with levels installed') }
        sprite(Image.soft)
        """, spectrum: spectrum)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(outcome.sprites.count == 1)
    }

    /// Different moments give different readings — the point of the whole thing.
    @Test("the reading follows the clock")
    func followsTheClock() {
        let spectrum = frames(count: 10, bands: 4, interval: 100)
        let outcome = run("""
        const a = audio.level(0, 0)
        const b = audio.level(500, 0)
        if (a === b) { throw new Error('the same reading at 0ms and 500ms: ' + a) }
        sprite(Image.soft)
        """, spectrum: spectrum)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// `range` averages, which is what "the bass" means.
    @Test("a range averages its bands")
    func rangeAverages() {
        let spectrum = frames(count: 4, bands: 4, interval: 100)
        let outcome = run("""
        // Frame 0: bands are 0.000, 0.001, 0.002, 0.003 — mean of 0…3 is 0.0015.
        const got = audio.range(0, 0, 3)
        if (Math.abs(got - 0.0015) > 1e-6) { throw new Error('range read ' + got) }
        // A single-band range is that band.
        const one = audio.range(0, 2, 2)
        if (Math.abs(one - 0.002) > 1e-6) { throw new Error('single read ' + one) }
        sprite(Image.soft)
        """, spectrum: spectrum)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// A whole frame at once, for a script laying a spectrum across the stage.
    @Test("a frame comes back as an array")
    func frameIsAnArray() {
        let spectrum = frames(count: 4, bands: 4, interval: 100)
        let outcome = run("""
        const f = audio.frame(100)
        if (f.length !== 4) { throw new Error('length ' + f.length) }
        if (Math.abs(f[1] - 0.011) > 1e-6) { throw new Error('frame[1] ' + f[1]) }
        sprite(Image.soft)
        """, spectrum: spectrum)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// Out-of-range arguments clamp rather than throw.
    ///
    /// A script asking past the end of its clip, or for a band that does not
    /// exist, is ordinary — a loop that runs one step long should not take the
    /// whole clip down with it.
    @Test("out-of-range reads clamp")
    func clamps() {
        let spectrum = frames(count: 4, bands: 4, interval: 100)
        let outcome = run("""
        const past = audio.level(999999, 0)     // beyond the last frame
        const last = audio.level(300, 0)
        if (past !== last) { throw new Error('past the end gave ' + past) }
        if (audio.level(0, 99) !== audio.level(0, 3)) { throw new Error('band clamp') }
        if (audio.level(-500, 0) !== audio.level(0, 0)) { throw new Error('negative clamp') }
        if (!isFinite(audio.level(NaN, NaN))) { throw new Error('NaN escaped') }
        sprite(Image.soft)
        """, spectrum: spectrum)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
    }

    /// With no analysis, `audio` is still there and reads zero.
    ///
    /// Installed even when empty on purpose: a script calling `audio.level` and
    /// getting "undefined is not a function" reads as a broken editor, where
    /// one getting zeros reads as a track that has not loaded — which is what
    /// it is. Same reasoning as the stand-in wave behind `AudioSpectrum` and
    /// the fallback glyph widths behind text.
    @Test("audio exists with no track loaded")
    func existsWithoutAudio() {
        let outcome = run("""
        if (typeof audio !== 'object') { throw new Error('audio is missing') }
        if (audio.isReal) { throw new Error('isReal true with no levels') }
        if (audio.level(0, 0) !== 0) { throw new Error('level is not zero') }
        if (audio.frame(0).length !== 0) { throw new Error('frame is not empty') }
        sprite(Image.soft)
        """, spectrum: nil)

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(outcome.sprites.count == 1, "a script still draws with no song")
    }

    /// The same script, run twice, reads the same thing.
    ///
    /// The preview and the exported `.osb` have to agree, which is the reason
    /// `Math.random` is locked shut — an audio reading that drifted between
    /// passes would break the same promise by another route.
    @Test("two passes read the same levels")
    func deterministic() {
        let spectrum = frames(count: 8, bands: 4, interval: 100)
        let source = """
        for (let i = 0; i < 8; i++) {
            sprite(Image.soft).fade(0, 100, 0, audio.level(i * 100, 1))
        }
        """
        let a = run(source, spectrum: spectrum)
        let b = run(source, spectrum: spectrum)

        func signature(_ outcome: ScriptRuntime.Outcome) -> [String] {
            outcome.sprites.flatMap { $0.commands.map { "\($0.payload)" } }
        }
        #expect(signature(a) == signature(b))
        #expect(!signature(a).isEmpty)
    }
}
