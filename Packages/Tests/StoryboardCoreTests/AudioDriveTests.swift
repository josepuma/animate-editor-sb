import Foundation
import Testing

@testable import StoryboardCore

/// Audio Drive: any clip's scale and opacity following the song's level.
///
/// Measured through the resolver — what the renderer would draw — against a
/// song built by hand, handed to the evaluator. Nothing here installs a
/// global: the analyser is the evaluator's own.
@Suite("Audio drive")
struct AudioDriveTests {
    /// Every band at `loud` inside the given song-time ranges, `quiet` outside.
    private func song(
        loudDuring ranges: [ClosedRange<Double>],
        loud: Float = 0.95,
        quiet: Float = 0.05,
    ) -> AudioSpectrum.Analyser {
        { range, bands, interval in
            let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
            let levels = (0 ..< count).map { frame -> [Float] in
                let time = range.lowerBound + Double(frame) * interval
                let level = ranges.contains { $0.contains(time) } ? loud : quiet
                return Array(repeating: level, count: bands)
            }
            return AudioSpectrum.Frames(levels: levels, interval: interval)
        }
    }

    /// One shape, stretched on purpose — a bar, not a square — so a filter
    /// that squared its subject would show.
    private func document(at start: Double = 0, duration: Double = 6000) -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: start, duration: duration)
        document.setValue(.number(300), for: ShapeEffect.Param.width, on: node.id)
        document.setValue(.number(60), for: ShapeEffect.Param.height, on: node.id)
        return (document, node.id)
    }

    private func driven(
        _ values: [String: EffectValue],
        at start: Double = 0,
        audio: AudioSpectrum.Analyser?,
    ) -> [StoryboardSprite] {
        var (document, clip) = document(at: start)
        let filter = document.addFilter(AudioDriveFilter.descriptor, to: clip)!
        for (id, value) in values {
            document.setFilterValue(value, for: id, on: filter.id, in: clip)
        }
        return EffectEvaluator(audio: audio).evaluate(document)
    }

    /// The one sprite's drawn state at a song time.
    private func state(_ sprites: [StoryboardSprite], at time: Double) -> SpriteRenderState? {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return states.first { $0.visible }
    }

    @Test("it is an audio filter in the standard library")
    func registered() {
        #expect(FilterLibrary.standard.filter(for: AudioDriveFilter.descriptor.type) != nil)
        #expect(AudioDriveFilter.descriptor.category == .audio)
    }

    /// Lands on clips that already exist, so at its defaults it must change
    /// nothing — not even rewrite the commands into an equivalent form.
    @Test("the defaults change nothing")
    func defaultsAreInert() {
        let (document, _) = document()
        let bare = EffectEvaluator(audio: song(loudDuring: [1000 ... 2000])).evaluate(document)
        let driven = driven([:], audio: song(loudDuring: [1000 ... 2000]))
        #expect(bare.map(\.commands.count) == driven.map(\.commands.count))
        for probe in stride(from: 0.0, through: 5900, by: 300) {
            #expect(state(bare, at: probe)?.scaleX == state(driven, at: probe)?.scaleX)
            #expect(state(bare, at: probe)?.opacity == state(driven, at: probe)?.opacity)
        }
    }

    @Test("scale grows with the song and keeps the subject's proportions")
    func scaleFollows() throws {
        let sprites = driven(
            [AudioDriveFilter.Param.scale: .number(1), AudioDriveFilter.Param.smoothing: .number(0)],
            audio: song(loudDuring: [2000 ... 3000]),
        )
        let quiet = try #require(state(sprites, at: 1000))
        let loud = try #require(state(sprites, at: 2500))

        #expect(loud.scaleX > quiet.scaleX * 1.5, "loud \(loud.scaleX), quiet \(quiet.scaleX)")
        // The bar keeps the proportions it had WITHOUT the filter. Comparing
        // the loud moment against the quiet one is not enough: a filter that
        // squared the bar squares it at both, and the two ratios agree. A first
        // version of this check did that, and passed with the bug in.
        let bare = try #require(state(EffectEvaluator().evaluate(document().0), at: 2500))
        let proportion = bare.scaleX / bare.scaleY
        #expect(proportion > 2, "the fixture is not a bar: \(proportion)")
        #expect(abs(loud.scaleX / loud.scaleY - proportion) < 0.01)
        #expect(abs(quiet.scaleX / quiet.scaleY - proportion) < 0.01)
    }

    /// Quiet dims, loud is the sprite's own opacity: the song lights it.
    @Test("dim darkens the quiet parts")
    func dimFollows() throws {
        let sprites = driven(
            [AudioDriveFilter.Param.dim: .number(0.8), AudioDriveFilter.Param.smoothing: .number(0)],
            audio: song(loudDuring: [2000 ... 3000]),
        )
        let quiet = try #require(state(sprites, at: 1000))
        let loud = try #require(state(sprites, at: 2500))
        #expect(loud.opacity > quiet.opacity + 0.5, "loud \(loud.opacity), quiet \(quiet.opacity)")
    }

    /// Smoothing is a slow release: after a hit the level falls off rather
    /// than cutting out, which is what stops a driven clip flickering.
    @Test("smoothing lets the level fall off after a hit")
    func smoothingReleases() throws {
        func scaleJustAfter(_ smoothing: Double) throws -> Double {
            let sprites = driven(
                [AudioDriveFilter.Param.scale: .number(1), AudioDriveFilter.Param.smoothing: .number(smoothing)],
                audio: song(loudDuring: [2000 ... 2500]),
            )
            return try #require(state(sprites, at: 2700)).scaleX
        }
        #expect(try scaleJustAfter(0.9) > scaleJustAfter(0) * 1.2)
    }

    /// It hears what plays UNDER the clip. Filters run in clip time, so the
    /// song has to be asked in song time — Beat Pulse got this wrong once.
    @Test("a clip placed later hears the song under it")
    func hearsSongTime() throws {
        let sprites = driven(
            [AudioDriveFilter.Param.scale: .number(1), AudioDriveFilter.Param.smoothing: .number(0)],
            at: 2000,
            audio: song(loudDuring: [3000 ... 4000]),
        )
        // Song time: loud at 3500, quiet at 5500.
        let loud = try #require(state(sprites, at: 3500))
        let quiet = try #require(state(sprites, at: 5500))
        #expect(loud.scaleX > quiet.scaleX * 1.5, "loud \(loud.scaleX), quiet \(quiet.scaleX)")
    }
}
