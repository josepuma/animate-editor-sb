import Foundation
import Testing

@testable import StoryboardCore

/// A bank of bars that rises and falls with the music — the thing every music
/// video has and every storyboard tool makes hard.
@Suite("Audio bars")
struct AudioBarsTests {
    private let evaluator = EffectEvaluator()

    private func document(duration: Double = 8000) -> EffectDocument {
        var document = EffectDocument()
        _ = document.add(AudioBarsEffect.descriptor, at: 0, duration: duration)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    /// Every scale command a sprite writes, in order.
    private func heights(of sprite: StoryboardSprite) -> [Double] {
        sprite.commands.compactMap { command in
            guard case let .vectorScale(_, _, _, endY) = command.payload else { return nil }
            return endY * AudioBarsEffect.sourceSize
        }
    }

    // ─── Layout ──────────────────────────────────────────────────────────────

    @Test("one sprite per bar")
    func oneSpritePerBar() {
        var document = document()
        document.setValue(.integer(16), for: AudioBarsEffect.Param.bands, on: clip(in: document))

        #expect(evaluator.evaluate(document).count == 16)
    }

    /// Laid out around the clip's centre, because a transform turns and scales
    /// about that point: a bank laid out from one corner would sweep one end
    /// round when rotated.
    @Test("the bank is centred on the clip")
    func bankIsCentred() {
        let sprites = evaluator.evaluate(document())
        let xs = sprites.map(\.defaultX).sorted()

        let middle = (xs.first! + xs.last!) / 2
        #expect(abs(middle - TransformProperty.x.defaultValue) < 0.001)
    }

    @Test("bars are spaced by width plus gap")
    func barsAreSpaced() {
        var document = document()
        let trackID = clip(in: document)
        document.setValue(.integer(4), for: AudioBarsEffect.Param.bands, on: trackID)
        document.setValue(.number(20), for: AudioBarsEffect.Param.width, on: trackID)
        document.setValue(.number(10), for: AudioBarsEffect.Param.gap, on: trackID)

        let xs = evaluator.evaluate(document).map(\.defaultX).sorted()
        for (left, right) in zip(xs, xs.dropFirst()) {
            #expect(abs(right - left - 30) < 0.001, "expected 30px spacing, got \(right - left)")
        }
    }

    /// The choice is where the bar's anchor sits, which is why it maps to a
    /// storyboard origin rather than to a position: a bar rooted at the bottom
    /// grows upward because that is where it is pinned.
    @Test("grounding sets the sprite's origin", arguments: AudioBarsEffect.Grounding.allCases)
    func groundingSetsOrigin(grounding: AudioBarsEffect.Grounding) {
        var document = document()
        document.setValue(
            .choice(grounding.rawValue),
            for: AudioBarsEffect.Param.origin,
            on: clip(in: document),
        )

        for sprite in evaluator.evaluate(document) {
            #expect(sprite.origin == grounding.origin)
        }
    }

    // ─── Motion ──────────────────────────────────────────────────────────────

    /// The whole point: the bars have to move.
    @Test("bars change height over the clip")
    func barsMove() {
        let sprites = evaluator.evaluate(document())
        let first = sprites.first!

        let tall = heights(of: first)
        #expect(tall.count > 10, "expected a reading per frame, got \(tall.count)")
        #expect(Set(tall.map { Int($0) }).count > 3, "the bar never moved")
    }

    /// Zero is a bar that vanishes between beats, which reads as the effect
    /// breaking rather than as quiet: a bank of bars is a row, and a row with
    /// holes in it is not one.
    @Test("a quiet bar keeps its rest height")
    func restHeightIsHonoured() {
        var document = document()
        let trackID = clip(in: document)
        document.setValue(.number(20), for: AudioBarsEffect.Param.floorHeight, on: trackID)
        document.setValue(.number(200), for: AudioBarsEffect.Param.height, on: trackID)

        for sprite in evaluator.evaluate(document) {
            for height in heights(of: sprite) {
                #expect(height >= 19.9, "a bar fell to \(height), below its rest height")
                #expect(height <= 200.1, "a bar reached \(height), above its peak")
            }
        }
    }

    /// The bar's width never changes, so it is one number for the life of the
    /// clip: only the height answers the music.
    @Test("only the height moves")
    func widthIsConstant() {
        var document = document()
        document.setValue(.number(24), for: AudioBarsEffect.Param.width, on: clip(in: document))

        for sprite in evaluator.evaluate(document) {
            let widths = sprite.commands.compactMap { command -> Double? in
                guard case let .vectorScale(startX, _, endX, _) = command.payload else { return nil }
                return abs(startX - endX) < 0.0001 ? startX : nil
            }
            #expect(widths.count > 1)
            #expect(Set(widths.map { Int($0 * 10_000) }).count == 1, "the width changed")
        }
    }

    /// Every analysed frame is a command per bar, so this is the number that
    /// decides whether the file opens.
    @Test("a lower frame rate writes fewer commands")
    func rateControlsCost() {
        func commandCount(rate: Int) -> Int {
            var document = document()
            document.setValue(.integer(rate), for: AudioBarsEffect.Param.rate, on: clip(in: document))
            return evaluator.evaluate(document).reduce(0) { $0 + $1.commands.count }
        }

        #expect(commandCount(rate: 10) < commandCount(rate: 40))
    }

    /// Bounded to its clip, which is the whole design: a bank spanning a
    /// five-minute song is a file osu! will not open.
    @Test("nothing is written past the clip")
    func staysInsideTheClip() {
        let sprites = evaluator.evaluate(document(duration: 4000))

        for sprite in sprites {
            for command in sprite.commands {
                #expect(command.endTime <= 4000.001, "a command ran to \(command.endTime)")
            }
        }
    }

    // ─── Without a track ─────────────────────────────────────────────────────

    /// Core cannot open an audio file, so the analyser is injected. The
    /// fallback is deliberate: a bank that moves to a placeholder still lays
    /// out, still animates and still shows what the parameters do, which is far
    /// better than an effect that draws nothing because nobody installed it.
    @Test("bars still animate with no analyser installed")
    func fallbackAnimates() {
        // Nothing is installed in tests, so this is the fallback path.
        #expect(AudioSpectrum.analyse == nil)

        let sprites = evaluator.evaluate(document())
        #expect(!sprites.isEmpty)

        let moved = heights(of: sprites.first!)
        #expect(Set(moved.map { Int($0) }).count > 3, "the placeholder did not move")
    }

    /// The same every time, so a preview does not shimmer.
    @Test("the placeholder is deterministic")
    func placeholderIsStable() {
        let first = evaluator.evaluate(document())
        let second = evaluator.evaluate(document())

        #expect(heights(of: first[0]) == heights(of: second[0]))
    }
}
