import Foundation
import Testing

@testable import StoryboardCore

/// Fade attenuates a clip as one thing.
@Suite("Fade")
struct FadeFilterTests {
    private let evaluator = EffectEvaluator()

    private func makeDocument(count: Int = 8, duration: Double = 2000) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: duration)
        document.setValue(.integer(count), for: EmitterEffect.Param.count, on: node.id)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    /// The opacity a sprite is drawn at, by walking its fade commands.
    private func opacity(of sprite: StoryboardSprite, at time: Double) -> Double? {
        var value: Double?
        for command in sprite.commands.filter({ $0.kind == .fade })
            .sorted(by: { $0.startTime < $1.startTime })
        {
            guard case let .fade(start, end) = command.payload else { continue }
            if time < command.startTime { break }
            if time >= command.endTime { value = end; continue }
            let span = command.endTime - command.startTime
            let progress = span > 0 ? (time - command.startTime) / span : 1
            value = easedLerp(start, end, progress, command.easing)
        }
        return value
    }

    /// The brightest thing on screen at `time` — the field's own level.
    private func peakOpacity(of sprites: [StoryboardSprite], at time: Double) -> Double {
        sprites.compactMap { opacity(of: $0, at: time) }.max() ?? 0
    }

    /// A filter landing in a finished project cannot change what it draws.
    @Test("the defaults change nothing")
    func defaultsAreInert() {
        var document = makeDocument()
        let before = evaluator.evaluate(document)

        _ = document.addFilter(FadeFilter.descriptor, to: clip(in: document))
        let after = evaluator.evaluate(document)

        #expect(before.count == after.count)
        // Compared as the picture, not the representation: what matters is that
        // nothing on screen moved, not that the commands match byte for byte.
        for probe in stride(from: 0.0, through: 2000, by: 200) {
            let was = peakOpacity(of: before, at: probe)
            let now = peakOpacity(of: after, at: probe)
            #expect(abs(was - now) < 0.001, "opacity moved at \(probe): \(was) to \(now)")
        }
        for (a, b) in zip(before, after) {
            #expect(a.id == b.id)
            #expect(a.commands.count == b.commands.count)
            for (one, two) in zip(a.commands, b.commands) {
                #expect(one.startTime == two.startTime)
                #expect(one.endTime == two.endTime)
                #expect(one.kind == two.kind)
            }
        }
    }

    /// The whole reason the filter exists: partway into a fade-in, *everything*
    /// on screen is dimmed — not just the sprites that happen to be young.
    ///
    /// An emitter already fades each particle over its own life, so a filter
    /// that only did that would be buying nothing.
    @Test("the field dims together during the fade in")
    func fadeInAttenuatesTheWholeField() {
        var document = makeDocument(count: 40, duration: 4000)
        let trackID = clip(in: document)
        let filter = document.addFilter(FadeFilter.descriptor, to: trackID)!

        let before = evaluator.evaluate(document)
        document.setFilterValue(
            .number(2000), for: FadeFilter.Param.fadeIn, on: filter.id, in: trackID,
        )
        let after = evaluator.evaluate(document)

        // A quarter into the fade, the brightest sprite should be near a
        // quarter of what it was.
        let plain = peakOpacity(of: before, at: 500)
        let faded = peakOpacity(of: after, at: 500)

        #expect(plain > 0.05, "the subject has to be visible for this to mean anything")
        #expect(faded < plain * 0.45, "expected the field dimmed, got \(faded) of \(plain)")
        #expect(faded > 0, "dimmed, not extinguished")
    }

    /// And the same at the other end, which is a separate branch of the
    /// envelope.
    @Test("the field dims together during the fade out")
    func fadeOutAttenuatesTheWholeField() {
        var document = makeDocument(count: 40, duration: 4000)
        let trackID = clip(in: document)
        let filter = document.addFilter(FadeFilter.descriptor, to: trackID)!

        let before = evaluator.evaluate(document)
        document.setFilterValue(
            .number(2000), for: FadeFilter.Param.fadeOut, on: filter.id, in: trackID,
        )
        let after = evaluator.evaluate(document)

        let end = before.flatMap { $0.commands.map(\.endTime) }.max()!
        let probe = end - 500

        let plain = peakOpacity(of: before, at: probe)
        let faded = peakOpacity(of: after, at: probe)

        #expect(plain > 0.05)
        #expect(faded < plain * 0.45, "expected the field dimmed, got \(faded) of \(plain)")
    }

    /// The middle of a clip is untouched — a fade is an entry and an exit, not
    /// a filter over the whole thing.
    @Test("the middle is left alone")
    func middleIsUntouched() {
        var document = makeDocument(count: 40, duration: 4000)
        let trackID = clip(in: document)
        let filter = document.addFilter(FadeFilter.descriptor, to: trackID)!

        let before = evaluator.evaluate(document)
        document.setFilterValue(
            .number(500), for: FadeFilter.Param.fadeIn, on: filter.id, in: trackID,
        )
        document.setFilterValue(
            .number(500), for: FadeFilter.Param.fadeOut, on: filter.id, in: trackID,
        )
        let after = evaluator.evaluate(document)

        let plain = peakOpacity(of: before, at: 2000)
        let faded = peakOpacity(of: after, at: 2000)

        #expect(abs(faded - plain) < 0.02, "expected \(plain) in the middle, got \(faded)")
    }

    /// A sprite with **no fade command at all** still has to dim.
    ///
    /// The envelope multiplies the fades a sprite already carries, so a subject
    /// that never wrote one has nothing to attenuate — and the clip would stay
    /// lit while the inspector said otherwise. This is the hole `BlurFilter`
    /// already paid for.
    ///
    /// Built by hand rather than from an effect: every effect in the library
    /// writes an opacity of some kind, so a real subject cannot reach this
    /// branch. An earlier version of this test used `ShapeEffect` and passed
    /// with the hold removed — the specimen hid the bug.
    @Test("a sprite with no fade command still dims")
    func coversSpritesWithoutFades() {
        var sprite = StoryboardSprite(
            id: "bare",
            layer: .foreground,
            origin: .centre,
            filePath: "sb/x.png",
            defaultX: 320,
            defaultY: 240,
        )
        sprite.commands = [Command(
            easing: .linear,
            startTime: 0,
            endTime: 4000,
            payload: .move(startX: 320, startY: 240, endX: 400, endY: 240),
        )]

        var node = FilterNode(id: "f1", type: FadeFilter.descriptor.type)
        node.values[FadeFilter.Param.fadeIn] = EffectValue.number(2000)
        let context = FilterContext(descriptor: FadeFilter.descriptor, node: node)

        let faded = FadeFilter().apply(to: [sprite], in: context)

        let early = peakOpacity(of: faded, at: 400)
        let late = peakOpacity(of: faded, at: 3000)

        #expect(late > 0.5, "the subject should be up by the middle, got \(late)")
        #expect(early < late * 0.5, "expected a ramp, got \(early) then \(late)")
    }

    /// Not one sprite more, whatever the fade: this is why the filter is worth
    /// having on a thousand-particle field.
    @Test("fade costs no sprites")
    func fadeIsFree() {
        var document = makeDocument(count: 40)
        let trackID = clip(in: document)
        let filter = document.addFilter(FadeFilter.descriptor, to: trackID)!

        let before = evaluator.evaluate(document).count
        document.setFilterValue(
            .number(600), for: FadeFilter.Param.fadeIn, on: filter.id, in: trackID,
        )
        document.setFilterValue(
            .number(600), for: FadeFilter.Param.fadeOut, on: filter.id, in: trackID,
        )
        let after = evaluator.evaluate(document).count

        #expect(before == after)
    }

    /// Two ramps longer than the clip would fight over the same instants, and
    /// osu! picks one rather than blending — so they scale down together.
    ///
    /// Measured with the clamp removed: a one-second clip asked for five
    /// seconds each way came out between 0.0 and 0.2 and was never visible at
    /// all. The clip has to still reach full brightness at its peak.
    @Test("overlapping fades are scaled to fit")
    func overlongFadesDoNotOverlap() {
        var sprite = StoryboardSprite(
            id: "bare", layer: .foreground, origin: .centre,
            filePath: "sb/x.png", defaultX: 320, defaultY: 240,
        )
        sprite.commands = [Command(
            easing: .linear, startTime: 0, endTime: 1000,
            payload: .fade(start: 1, end: 1),
        )]

        var node = FilterNode(id: "f1", type: FadeFilter.descriptor.type)
        node.values[FadeFilter.Param.fadeIn] = EffectValue.number(5000)
        node.values[FadeFilter.Param.fadeOut] = EffectValue.number(5000)
        let context = FilterContext(descriptor: FadeFilter.descriptor, node: node)

        let faded = FadeFilter().apply(to: [sprite], in: context)

        // The brightest the clip ever gets, sampled across its whole span.
        let peak = stride(from: 0.0, through: 1000, by: 25)
            .map { peakOpacity(of: faded, at: $0) }
            .max() ?? 0

        #expect(peak > 0.9, "a clamped pair should still reach full, got \(peak)")
    }
}
