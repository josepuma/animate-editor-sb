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
    @Test("silence draws a flat, still line", arguments: ["Zigzag", "Flowing", "Signal"])
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
    @Test("a louder song draws a taller wave", arguments: ["Zigzag", "Flowing", "Signal"])
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

    // ─── Signal: a waveform rebuilt from the spectrum ────────────────────────

    /// The heights of one strand's samples at a moment, left to right.
    private func profile(_ sprites: [StoryboardSprite], at time: Double, strand: Int = 0) -> [Double] {
        states(sprites.filter { $0.id.contains("/s\(strand)/dot") }, at: time)
            .sorted { $0.x < $1.x }
            .map { centre.y - $0.y }
    }

    private func signal(_ extra: [String: EffectValue] = [:]) -> [String: EffectValue] {
        [
            AudioWavesEffect.Param.style: .choice("Signal"),
            AudioWavesEffect.Param.drawAs: .choice("Dots"),
            AudioWavesEffect.Param.samples: .integer(96),
        ].merging(extra) { $1 }
    }

    private func crossings(_ ys: [Double]) -> [Int] {
        ys.indices.dropFirst().filter { ys[$0 - 1] * ys[$0] < 0 }
    }

    /// Reported as "it looks like it only bounces": a saw alternates on every
    /// point, at a fixed rhythm. A signal crosses the line where its sum of
    /// frequencies happens to, which is irregular.
    @Test("a signal crosses the line irregularly, not as a saw")
    func signalIsIrregular() {
        let ys = profile(waves(signal(), audio: song(level: 0.8)), at: 1000)
        let at = crossings(ys)
        #expect(Double(at.count) < Double(ys.count - 1) * 0.6, "\(at.count) crossings in \(ys.count) samples — a saw")
        let gaps = zip(at, at.dropFirst()).map { $1 - $0 }
        #expect(Set(gaps).count > 2, "crossings evenly spaced: \(gaps)")
    }

    /// Each band is a frequency: the bass draws long waves, the treble a fine
    /// ripple. Heard one band at a time, the treble crosses far more often.
    @Test("the bass draws long waves and the treble a fine ripple")
    func bandsAreFrequencies() {
        let points = 32
        func count(_ band: Int) -> Int {
            crossings(profile(waves(signal([AudioWavesEffect.Param.points: .integer(points)]),
                                    audio: song(level: 0, loudBand: band)), at: 1000)).count
        }
        #expect(count(points - 2) > count(1) * 3, "treble \(count(points - 2)), bass \(count(1))")
    }

    /// The other half of the report: "waves that only move left to right". A
    /// travelling wave is the previous frame slid sideways; measured by the
    /// best slide that explains the next frame from this one. For Flowing it
    /// explains almost everything — which is the point of checking it too:
    /// the measure has to be able to see a travelling wave before its
    /// verdict on Signal means anything.
    @Test("a signal vibrates instead of travelling", arguments: [("Flowing", false), ("Signal", true)])
    func vibratesNotTravels(style: String, vibrates: Bool) {
        // A flow worth seeing: at the default a phase barely turns in 200ms,
        // and a frame that hardly changed is explained by any slide at all.
        let values = signal([
            AudioWavesEffect.Param.style: .choice(style),
            AudioWavesEffect.Param.flow: .number(1.5),
        ])
        let sprites = waves(values, audio: song(level: 0.8))
        let a = profile(sprites, at: 1000), b = profile(sprites, at: 1200)
        let energy = a.map(abs).reduce(0, +) / Double(a.count)

        var best = Double.infinity
        for shift in -24 ... 24 {
            var total = 0.0, n = 0
            for i in a.indices where b.indices.contains(i + shift) {
                total += abs(b[i + shift] - a[i]); n += 1
            }
            best = min(best, total / Double(max(1, n)))
        }
        let unexplained = best / max(energy, 1e-9)
        if vibrates {
            #expect(unexplained > 0.3, "\(style): a slide explains the next frame (\(unexplained))")
        } else {
            #expect(unexplained < 0.15, "the measure cannot see a travelling wave (\(unexplained))")
        }
    }

    /// On a line the signal gathers to the line at its two ends, the way a
    /// trace does on a scope's screen.
    @Test("a signal gathers to the line at its ends")
    func signalTapers() {
        let ys = profile(waves(signal(), audio: song(level: 0.9)), at: 1000)
        let peak = ys.map(abs).max() ?? 0
        #expect(abs(ys.first ?? 1) < peak * 0.1 && abs(ys.last ?? 1) < peak * 0.1)
    }

    /// Strands braid: each mixes the bands with phases of its own, so they
    /// cross one another rather than riding as shifted copies.
    @Test("strands of a signal braid rather than copy")
    func strandsBraid() {
        let sprites = waves(signal([
            AudioWavesEffect.Param.strands: .integer(2),
            AudioWavesEffect.Param.lag: .number(0),
            AudioWavesEffect.Param.spread: .number(0),
        ]), audio: song(level: 0.8))
        let a = profile(sprites, at: 1000, strand: 0), b = profile(sprites, at: 1000, strand: 1)
        let crossing = zip(a, b).map { $0 - $1 }
        #expect(crossings(crossing).count >= 2, "the strands never cross")
    }

    /// The best slide from one frame to the next, in samples, and how well it
    /// fits — by normalised correlation.
    ///
    /// Not by absolute difference, which is what the first version used and
    /// what made it lie. A standing wave changing its swing is the same shape
    /// scaled, and a difference punishes scaling: sliding the comparison so it
    /// covers less of the line lowered the error, and that read as a slide of
    /// two to four samples every frame — on something that cannot move at all.
    /// Correlation does not care about scale, so a scaled copy fits perfectly
    /// where it is.
    private func slide(_ a: [Double], _ b: [Double]) -> (shift: Int, fit: Double) {
        var best = (shift: 0, fit: -Double.infinity)
        for shift in -12 ... 12 {
            let pairs = a.indices.compactMap { i -> (Double, Double)? in
                b.indices.contains(i + shift) ? (a[i], b[i + shift]) : nil
            }
            guard pairs.count > a.count / 2 else { continue }
            let ma = pairs.map(\.0).reduce(0, +) / Double(pairs.count)
            let mb = pairs.map(\.1).reduce(0, +) / Double(pairs.count)
            var num = 0.0, da = 0.0, db = 0.0
            for (x, y) in pairs {
                num += (x - ma) * (y - mb); da += (x - ma) * (x - ma); db += (y - mb) * (y - mb)
            }
            let fit = num / max((da * db).squareRoot(), 1e-12)
            if fit > best.fit { best = (shift, fit) }
        }
        return best
    }

    /// "Waves that only move left to right": a slide that keeps going the same
    /// way, frame after frame. The earlier check — can one slide explain the
    /// next frame? — passed a signal whose bands all turned the same way,
    /// because bands at different speeds deform and no single slide fits;
    /// yet the line as a whole still drifted to one side. What tells a drift
    /// from a vibration is that a drift keeps a DIRECTION.
    @Test("a signal has no side to drift towards", arguments: [("Flowing", true), ("Signal", false)])
    func noDirection(style: String, drifts: Bool) {
        let sprites = waves(signal([
            AudioWavesEffect.Param.style: .choice(style),
            AudioWavesEffect.Param.flow: .number(1.5),
        ]), audio: song(level: 0.8))
        let times = stride(from: 1000.0, through: 1800, by: 100).map { $0 }
        // A frame pair drifts when a slide explains it almost perfectly and the
        // slide is not zero. Drifting one way is every pair doing so, the
        // same way.
        let slides = zip(times, times.dropFirst()).map { slide(profile(sprites, at: $0), profile(sprites, at: $1)) }
        let drifting = slides.filter { $0.fit > 0.9 && $0.shift != 0 }.map(\.shift)
        let oneWay = drifting.count == slides.count
            && (drifting.allSatisfy { $0 > 0 } || drifting.allSatisfy { $0 < 0 })
        if drifts {
            #expect(oneWay, "the measure cannot see Flowing drift: \(slides)")
        } else {
            #expect(!oneWay, "\(style) drifts one way: \(slides)")
        }
    }
}
