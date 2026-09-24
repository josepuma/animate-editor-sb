import Foundation
import Testing

@testable import StoryboardCore

/// Signal Loss: an old television losing its picture.
///
/// Each check measures the sprites, the way the renderer would draw them. The
/// ones that matter most are about WHEN: a burst trigger glitches in bursts
/// and holds still between them, a hits trigger glitches on the song's hits
/// and nowhere else, and static jumps rather than slides — a square gliding
/// across the frame reads as a particle, not as noise.
@Suite("Signal loss")
struct SignalLossTests {
    private func node(_ values: [String: EffectValue], duration: Double = 6000, seed: UInt64 = 7) -> EffectNode {
        EffectNode(
            id: "tv", type: SignalLossEffect.descriptor.type, name: "TV",
            startTime: 0, duration: duration, seed: seed,
            values: SignalLossEffect.descriptor.defaultValues.merging(values) { $1 },
        )
    }

    private func states(_ sprites: [StoryboardSprite], at time: Double, matching part: String) -> [SpriteRenderState] {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return states.filter { $0.visible && $0.opacity > 0.02 && $0.spriteId.contains(part) }
    }

    /// A song whose bass kicks at the given song times and is quiet otherwise.
    private func kicks(_ times: [Double]) -> AudioSpectrum.Analyser {
        { range, bands, interval in
            let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
            let levels = (0 ..< count).map { frame -> [Float] in
                let time = range.lowerBound + Double(frame) * interval
                let hit = times.reduce(Float(0.05)) { level, kick in
                    let since = time - kick
                    return since >= 0 && since < 300 ? max(level, Float(0.95 * pow(0.5, since / interval))) : level
                }
                return (0 ..< bands).map { $0 < 6 ? hit : 0.1 }
            }
            return AudioSpectrum.Frames(levels: levels, interval: interval)
        }
    }

    private let noisy: [String: EffectValue] = [
        SignalLossEffect.Param.noise: .integer(60),
        SignalLossEffect.Param.scanlines: .toggle(false),
        SignalLossEffect.Param.rollingBand: .toggle(false),
    ]

    @Test("it is registered in the standard library")
    func registered() {
        #expect(EffectLibrary.standard.descriptor(for: SignalLossEffect.descriptor.type) != nil)
    }

    /// Constant: no signal at all, so the static never stops.
    @Test("a constant loss is static all the way through")
    func constantNeverStops() {
        let sprites = EffectEvaluator().evaluate(node(noisy.merging([
            SignalLossEffect.Param.trigger: .choice("Constant"),
        ]) { $1 }))
        for time in stride(from: 200.0, through: 5800, by: 400) {
            #expect(!states(sprites, at: time, matching: "/noise").isEmpty, "no static at \(time)")
        }
    }

    /// Bursts: the picture breaks up, then holds. Both have to happen — a
    /// burst trigger that never rests is Constant with another name.
    @Test("bursts break up the picture and then rest")
    func burstsRest() {
        let sprites = EffectEvaluator().evaluate(node(noisy.merging([
            SignalLossEffect.Param.trigger: .choice("Bursts"),
        ]) { $1 }, duration: 12_000))
        let samples = stride(from: 25.0, through: 11_975, by: 50).map {
            !states(sprites, at: $0, matching: "/noise").isEmpty
        }
        let glitching = samples.filter { $0 }.count
        #expect(glitching > 5, "no bursts at all")
        #expect(glitching < samples.count * 3 / 4, "it never rests: \(glitching) of \(samples.count) frames")
    }

    /// Hits: the signal drops where the song hits, and nowhere else.
    @Test("on hits it glitches on the kicks and holds between them")
    func hitsTrigger() {
        let kickTimes = [1000.0, 2600, 4300]
        var node = node(noisy.merging([
            SignalLossEffect.Param.trigger: .choice("Hits"),
            SignalLossEffect.Param.burstLength: .number(250),
        ]) { $1 })
        node.startTime = 0
        let sprites = EffectEvaluator(audio: kicks(kickTimes)).evaluate(node)

        for kick in kickTimes {
            #expect(!states(sprites, at: kick + 100, matching: "/noise").isEmpty, "no glitch on the kick at \(kick)")
        }
        // Everywhere else, every 50ms — not at a few chosen instants. A
        // version checking four quiet moments passed with glitches added at
        // times that happened to fall between them.
        let near = { (time: Double) in kickTimes.contains { time >= $0 - 70 && time <= $0 + 250 + 70 } }
        for time in stride(from: 25.0, through: 5975, by: 50) where !near(time) {
            #expect(states(sprites, at: time, matching: "/noise").isEmpty, "a glitch at \(time) with no kick")
        }
    }

    /// Static jumps. Every move it writes is instant; a square gliding
    /// between two places reads as a particle drifting.
    @Test("static jumps instead of sliding")
    func staticJumps() {
        let sprites = EffectEvaluator().evaluate(node(noisy.merging([
            SignalLossEffect.Param.trigger: .choice("Constant"),
        ]) { $1 }))
        let moves = sprites.filter { $0.id.contains("/noise") }.flatMap(\.commands).filter { $0.kind == .move }
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.startTime == $0.endTime }, "a static square slides")
    }

    @Test("the same seed breaks up the same way; another seed does not")
    func seeded() {
        let values = noisy.merging([SignalLossEffect.Param.trigger: .choice("Bursts")]) { $1 }
        let a = EffectEvaluator().evaluate(node(values, seed: 7))
        let b = EffectEvaluator().evaluate(node(values, seed: 7))
        let c = EffectEvaluator().evaluate(node(values, seed: 8))
        func bursts(_ s: [StoryboardSprite]) -> [Bool] {
            stride(from: 25.0, through: 5975, by: 50).map { !states(s, at: $0, matching: "/noise").isEmpty }
        }
        #expect(bursts(a) == bursts(b))
        #expect(bursts(a) != bursts(c))
    }

    /// Scanlines run the full height, evenly, and hold still.
    @Test("scanlines cover the frame evenly")
    func scanlines() {
        let sprites = EffectEvaluator().evaluate(node([
            SignalLossEffect.Param.scanlines: .toggle(true),
            SignalLossEffect.Param.scanlineSpacing: .number(6),
            SignalLossEffect.Param.noise: .integer(0),
        ]))
        let ys = states(sprites, at: 3000, matching: "/scan").map(\.y).sorted()
        #expect(ys.count >= 480 / 6 - 1, "\(ys.count) scanlines")
        let gaps = Set(zip(ys, ys.dropFirst()).map { Int(($1 - $0).rounded()) })
        #expect(gaps == [6], "uneven scanlines: \(gaps)")
    }

    /// The seven bars of "no signal", left to right, across the frame.
    @Test("the test pattern is seven bars across the frame")
    func testPattern() {
        let sprites = EffectEvaluator().evaluate(node([
            SignalLossEffect.Param.testPattern: .toggle(true),
            SignalLossEffect.Param.noise: .integer(0),
        ]))
        let bars = states(sprites, at: 3000, matching: "/pattern")
        #expect(bars.count == 7)
        let xs = bars.map(\.x).sorted()
        #expect((xs.last ?? 0) - (xs.first ?? 0) > 600)
    }

    /// Every step of static is a command per square, so it is held to a
    /// section's worth even in its heaviest mode.
    @Test("a constant loss stays within a section's cost")
    func affordable() {
        let sprites = EffectEvaluator().evaluate(node([SignalLossEffect.Param.trigger: .choice("Constant")], duration: 8000))
        let commands = sprites.reduce(0) { $0 + $1.commands.count }
        #expect(commands <= 20_000, "\(commands) commands")
    }
}
