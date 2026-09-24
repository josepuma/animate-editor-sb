import Foundation
import Testing

@testable import StoryboardCore

/// Audio Waves: a line — or strands of lines — drawn by the song.
///
/// The promise these check first is the one that matters: **the shape comes
/// from the music**. Every point's amplitude is its band's level at that
/// moment; the style decides how that energy is drawn, and nothing in it moves
/// on its own. So silence is a still, flat line, and every check below is
/// measured off the sprites against a song built by hand.
@Suite("Audio waves")
struct AudioWavesTests {
    private let centre = (x: 320.0, y: 240.0)

    /// Every band at `level`, or one band loud and the rest silent.
    private func song(level: Float = 0, loudBand: Int? = nil, loud: Float = 0.9) -> AudioSpectrum.Analyser {
        { range, bands, interval in
            let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
            return AudioSpectrum.Frames(
                levels: Array(repeating: (0 ..< bands).map { $0 == loudBand ? loud : level }, count: count),
                interval: interval,
            )
        }
    }

    /// Loud from `from` ms of song time on, silent before.
    private func swell(from: Double) -> AudioSpectrum.Analyser {
        { range, bands, interval in
            let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
            let levels = (0 ..< count).map { frame -> [Float] in
                let time = range.lowerBound + Double(frame) * interval
                return Array(repeating: time >= from ? 0.9 : 0, count: bands)
            }
            return AudioSpectrum.Frames(levels: levels, interval: interval)
        }
    }

    private func waves(
        _ values: [String: EffectValue],
        audio: @escaping AudioSpectrum.Analyser,
        start: Double = 0,
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        let node = document.add(AudioWavesEffect.descriptor, at: start, duration: 2000)
        for (id, value) in values { document.setValue(value, for: id, on: node.id) }
        return EffectEvaluator(audio: audio).evaluate(document)
    }

    private func states(_ sprites: [StoryboardSprite], at time: Double) -> [SpriteRenderState] {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return states.filter(\.visible)
    }

    private let dots: [String: EffectValue] = [AudioWavesEffect.Param.drawAs: .choice("Dots")]

    @Test("it is an audio effect in the standard library")
    func registered() {
        #expect(EffectLibrary.standard.descriptor(for: AudioWavesEffect.descriptor.type) != nil)
        #expect(AudioWavesEffect.descriptor.category == .audio)
    }

    // ─── It reacts to the music, and only to it ──────────────────────────────

    /// Silence is a flat line, and a still one — whatever the style.
    @Test("silence draws a flat, still line", arguments: ["Zigzag", "Flowing"])
    func silenceIsFlat(style: String) {
        let sprites = waves(dots.merging([AudioWavesEffect.Param.style: .choice(style)]) { $1 }, audio: song(level: 0))
        for time in [100.0, 900, 1700] {
            for state in states(sprites, at: time) {
                #expect(abs(state.y - centre.y) < 0.5, "\(style): a point sits at \(state.y) in silence")
            }
        }
    }

    /// The same clip under a quiet song and a loud one: the loud one reaches
    /// further from the line.
    @Test("a louder song draws a taller wave", arguments: ["Zigzag", "Flowing"])
    func louderIsTaller(style: String) {
        func reach(_ level: Float) -> Double {
            let values = dots.merging([AudioWavesEffect.Param.style: .choice(style)]) { $1 }
            return states(waves(values, audio: song(level: level)), at: 1000)
                .map { abs($0.y - centre.y) }.max() ?? 0
        }
        #expect(reach(0.9) > reach(0.2) * 2, "\(style): loud \(reach(0.9)), quiet \(reach(0.2))")
    }

    /// Each point is its own band: a single loud band lifts one place on the
    /// line, not the whole of it.
    @Test("each point answers its own band")
    func pointsAreBands() {
        let points = 16
        let sprites = waves([
            AudioWavesEffect.Param.drawAs: .choice("Dots"),
            AudioWavesEffect.Param.points: .integer(points),
        ], audio: song(level: 0, loudBand: 3))
        let lifted = states(sprites, at: 1000).filter { abs($0.y - centre.y) > 5 }
        #expect(lifted.count == 1, "\(lifted.count) points lifted by one band")
    }

    /// Zigzag alternates: neighbouring points go opposite ways, which is what
    /// draws the saw of the first reference.
    @Test("zigzag alternates its points")
    func zigzagAlternates() {
        let sprites = waves(dots.merging([AudioWavesEffect.Param.style: .choice("Zigzag")]) { $1 }, audio: song(level: 0.8))
        let ys = states(sprites, at: 1000).sorted { $0.x < $1.x }.map { $0.y - centre.y }
        for (a, b) in zip(ys, ys.dropFirst()) {
            #expect(a * b < 0, "two neighbours on the same side: \(a), \(b)")
        }
    }

    // ─── Strands ─────────────────────────────────────────────────────────────

    /// A strand behind hears the same song later. With the song turning loud
    /// at 1000ms, the lead strand is up by 1100 while one lagging 400ms is
    /// still flat — the delay is what makes strands flow instead of moving as
    /// one block.
    @Test("a lagging strand hears the song later")
    func strandsLag() {
        let sprites = waves([
            AudioWavesEffect.Param.drawAs: .choice("Dots"),
            AudioWavesEffect.Param.strands: .integer(2),
            AudioWavesEffect.Param.lag: .number(400),
            AudioWavesEffect.Param.spread: .number(0),
        ], audio: swell(from: 1000))
        let lead = sprites.filter { $0.id.contains("/s0/") }
        let behind = sprites.filter { $0.id.contains("/s1/") }
        #expect(!lead.isEmpty && !behind.isEmpty)

        let leadReach = states(lead, at: 1150).map { abs($0.y - centre.y) }.max() ?? 0
        let behindReach = states(behind, at: 1150).map { abs($0.y - centre.y) }.max() ?? 0
        #expect(leadReach > 20, "the lead strand has not heard the song: \(leadReach)")
        #expect(behindReach < 1, "the lagging strand heard it early: \(behindReach)")
    }

    @Test("strands behind are fainter")
    func strandsFade() {
        let sprites = waves([
            AudioWavesEffect.Param.drawAs: .choice("Dots"),
            AudioWavesEffect.Param.strands: .integer(4),
            AudioWavesEffect.Param.falloff: .number(0.8),
        ], audio: song(level: 0.5))
        let all = states(sprites, at: 1000)
        let lead = all.filter { $0.spriteId.contains("/s0/") }.map(\.opacity).max() ?? 0
        let last = all.filter { $0.spriteId.contains("/s3/") }.map(\.opacity).max() ?? 0
        #expect(last < lead * 0.5, "lead \(lead), last \(last)")
    }

    // ─── Lines ───────────────────────────────────────────────────────────────

    /// A line is segments, and a segment has to run from one point to the
    /// next — measured with the shader's own rotation: up is (0, −1), turned
    /// to (sin r, −cos r).
    @Test("line segments join consecutive points")
    func segmentsJoin() {
        let values: [String: EffectValue] = [
            AudioWavesEffect.Param.drawAs: .choice("Both"),
            AudioWavesEffect.Param.style: .choice("Zigzag"),
            AudioWavesEffect.Param.points: .integer(8),
        ]
        let sprites = waves(values, audio: song(level: 0.7))
        let now = states(sprites, at: 1000)
        let points = now.filter { $0.spriteId.contains("/dot") }.map { (x: $0.x, y: $0.y) }
        let segments = now.filter { $0.spriteId.contains("/seg") }
        #expect(segments.count == points.count - 1)

        for segment in segments {
            let half = segment.scaleY * AudioWavesEffect.segmentSource / 2
            let ends = [
                (x: segment.x + sin(segment.rotation) * half, y: segment.y - cos(segment.rotation) * half),
                (x: segment.x - sin(segment.rotation) * half, y: segment.y + cos(segment.rotation) * half),
            ]
            for end in ends {
                let nearest = points.map { hypot($0.x - end.x, $0.y - end.y) }.min() ?? .infinity
                #expect(nearest < 1, "a segment ends \(nearest)px from any point")
            }
        }
    }

    @Test("a circle wave sits on its ring in silence")
    func circleRing() {
        let sprites = waves([
            AudioWavesEffect.Param.drawAs: .choice("Dots"),
            AudioWavesEffect.Param.layout: .choice("Circle"),
            AudioWavesEffect.Param.radius: .number(110),
        ], audio: song(level: 0))
        for state in states(sprites, at: 1000) {
            #expect(abs(hypot(state.x - centre.x, state.y - centre.y) - 110) < 0.5)
        }
    }

    /// It hears what plays UNDER it, in song time.
    @Test("a clip placed later hears the song under it")
    func songTime() {
        let sprites = waves(dots, audio: swell(from: 3000), start: 2500)
        let before = states(sprites, at: 2800).map { abs($0.y - centre.y) }.max() ?? 0
        let after = states(sprites, at: 3500).map { abs($0.y - centre.y) }.max() ?? 0
        #expect(before < 1 && after > 20, "before \(before), after \(after)")
    }
}
