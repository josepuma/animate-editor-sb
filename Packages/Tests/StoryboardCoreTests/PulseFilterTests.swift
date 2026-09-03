import Foundation
import Testing

@testable import StoryboardCore

/// The filter that connects a storyboard to the song it plays over.
///
/// Its whole claim is that it reads the map's tempo rather than asking anyone
/// to type it: a pulse that needs a BPM copied by hand drifts over five
/// minutes, and drifting is exactly the failure nobody notices until the file
/// is published.
@Suite("Beat pulse")
struct PulseFilterTests {
    /// A map at a flat 150 BPM, first beat at one second.
    private var timing: BeatmapTimingData {
        BeatmapTimingData(uninheritedPoints: [
            UninheritedTimingPoint(time: 1000, beatLength: 400, meter: 4, kiai: false),
        ])
    }

    /// One shape on one track, five seconds long.
    private func document() -> EffectDocument {
        var document = EffectDocument()
        _ = document.add(ShapeEffect.descriptor, at: 0, duration: 5000)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    /// The hits, in order.
    ///
    /// Only the commands that actually change the scale: the filter also writes
    /// flat holds between beats, so a sprite has no stretch without a command
    /// saying where it is — and reading those as hits makes every assertion
    /// about spacing and curve nonsense.
    private func scales(_ sprites: [StoryboardSprite]) -> [Command] {
        sprites
            .flatMap(\.commands)
            .filter { command in
                // Both spellings: a pulse on a stretched sprite writes `_V`
                // rather than `_S`, and a test that only looked for one would
                // pass while the filter squared its subject.
                switch command.payload {
                case let .scale(start, end):
                    return abs(start - end) > 0.0001
                case let .vectorScale(startX, _, endX, _):
                    return abs(startX - endX) > 0.0001
                default:
                    return false
                }
            }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Where a scale command starts, whichever way it is spelled.
    private static func peak(_ command: Command) -> Double? {
        switch command.payload {
        case let .scale(start, _): start
        case let .vectorScale(startX, _, _, _): startX
        default: nil
        }
    }

    /// Where it ends.
    private static func rest(_ command: Command) -> Double? {
        switch command.payload {
        case let .scale(_, end): end
        case let .vectorScale(_, _, endX, _): endX
        default: nil
        }
    }

    private func fades(_ sprites: [StoryboardSprite]) -> [Command] {
        sprites
            .flatMap(\.commands)
            .filter { $0.kind == .fade }
            .sorted { $0.startTime < $1.startTime }
    }

    // ─── It is a filter ──────────────────────────────────────────────────────

    /// A pulse is a *behaviour*, not a thing.
    ///
    /// Written as an effect first, where it could only beat a disc of its own.
    /// As a filter it beats whatever is already on the track — the logo, the
    /// title, the particle field — and the disc is still available, because a
    /// Shape with this on it is exactly that.
    @Test("the pulse is registered as a filter and not as an effect")
    func registeredAsAFilter() {
        #expect(FilterLibrary.standard.filter(for: PulseFilter.descriptor.type) != nil)
        #expect(EffectLibrary.standard.effect(for: PulseFilter.descriptor.type) == nil)
    }

    /// One sprite in, one sprite out. This is what makes it cheap enough to put
    /// on an emitter, where a filter that added copies would multiply hundreds.
    @Test("pulsing adds no sprites")
    func addsNoSprites() {
        var document = document()
        let trackID = clip(in: document)
        let evaluator = EffectEvaluator()

        let before = evaluator.evaluate(document).count
        _ = document.addFilter(PulseFilter.descriptor, to: trackID)

        #expect(evaluator.evaluate(document).count == before)
    }

    // ─── Following the song ──────────────────────────────────────────────────

    /// The reason it is worth having at all: the tempo comes from the map.
    @Test("it beats on the map's tempo without being told one")
    func followsTheBeatmap() {
        var document = document()
        let trackID = clip(in: document)
        _ = document.addFilter(PulseFilter.descriptor, to: trackID)

        var evaluator = EffectEvaluator()
        evaluator.beat = BeatGrid(timing: timing)

        let hits = scales(evaluator.evaluate(document))
        #expect(hits.count > 4, "expected a hit per beat, got \(hits.count)")

        // 400ms apart, which is 150 BPM — not the 120 BPM fallback.
        let spacing = zip(hits, hits.dropFirst()).map { $1.startTime - $0.startTime }
        for gap in spacing {
            #expect(abs(gap - 400) < 1, "hits \(gap)ms apart, expected 400")
        }
    }

    /// A stated tempo wins: someone who types a number means it, and a pulse
    /// deliberately off the beat is as legitimate as one on it.
    @Test("a stated BPM overrides the song")
    func statedBPMWins() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(60), for: PulseFilter.Param.bpm, on: filter.id, in: trackID)

        var evaluator = EffectEvaluator()
        evaluator.beat = BeatGrid(timing: timing)

        let hits = scales(evaluator.evaluate(document))
        let spacing = zip(hits, hits.dropFirst()).map { $1.startTime - $0.startTime }
        for gap in spacing {
            #expect(abs(gap - 1000) < 1, "hits \(gap)ms apart, expected 1000 at 60 BPM")
        }
    }

    /// A map with no timing points is still a map. Without a fallback the
    /// filter would silently do nothing, which reads as broken rather than as
    /// missing data.
    @Test("with no song and no BPM it still beats")
    func fallsBackToATempo() {
        var document = document()
        let trackID = clip(in: document)
        _ = document.addFilter(PulseFilter.descriptor, to: trackID)

        #expect(!scales(EffectEvaluator().evaluate(document)).isEmpty)
    }

    /// Named in beats rather than milliseconds so the interval survives a tempo
    /// change — "every two beats" means the same thing at any speed.
    @Test("a wider interval beats less often")
    func intervalWidensTheGap() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!

        var evaluator = EffectEvaluator()
        evaluator.beat = BeatGrid(timing: timing)

        let everyBeat = scales(evaluator.evaluate(document)).count

        document.setFilterValue(
            .choice(PulseFilter.Interval.everyFour.rawValue),
            for: PulseFilter.Param.every, on: filter.id, in: trackID,
        )
        let everyFour = scales(evaluator.evaluate(document)).count

        #expect(everyFour < everyBeat, "every 4 beats fired \(everyFour), every beat \(everyBeat)")
    }

    // ─── What it writes ──────────────────────────────────────────────────────

    /// The kick lands and settles, rather than growing into the next beat.
    @Test("each hit falls back to rest")
    func eachHitSettles() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.5), for: PulseFilter.Param.punch, on: filter.id, in: trackID)

        for command in scales(EffectEvaluator().evaluate(document)) {
            guard let peak = Self.peak(command), let rest = Self.rest(command) else { continue }
            #expect(peak > rest, "a hit must fall, got \(peak) → \(rest)")
        }
    }

    /// The punch is a multiplier on whatever size the subject already is.
    ///
    /// A shape drawn at half size has to kick from half size rather than snap
    /// to full — otherwise adding a pulse silently resizes the thing it was
    /// meant to animate. Checked as a ratio against the same clip unpulsed,
    /// because the resting scale is whatever the shape's own size works out to
    /// and naming that number here would be testing the shape, not the pulse.
    @Test("the punch scales from the sprite's own size")
    func punchIsRelative() {
        var document = document()
        let trackID = clip(in: document)
        let evaluator = EffectEvaluator()

        let restingScale = evaluator.evaluate(document)
            .flatMap(\.commands)
            .compactMap(Self.peak)
            .first ?? 1

        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(1), for: PulseFilter.Param.punch, on: filter.id, in: trackID)

        let peaks = scales(evaluator.evaluate(document)).compactMap(Self.peak)

        #expect(!peaks.isEmpty)
        for peak in peaks {
            // Twice the size it already was — not twice one.
            #expect(
                abs(peak - restingScale * 2) < 0.01,
                "peak \(peak) ignores the sprite's own scale of \(restingScale)",
            )
        }
    }

    /// Two scale commands overlapping in time fight over one property and one
    /// wins at each instant — the same collision the wiggle had with movement.
    /// The beats have to take the scale over rather than sit beside it.
    @Test("the beats replace the sprite's scale rather than overlapping it")
    func doesNotOverlapScale() {
        var document = document()
        let trackID = clip(in: document)
        _ = document.addFilter(PulseFilter.descriptor, to: trackID)

        for sprite in EffectEvaluator().evaluate(document) {
            let scales = sprite.commands
                .filter { $0.kind == .scale || $0.kind == .vectorScale }
                .sorted { $0.startTime < $1.startTime }

            for (earlier, later) in zip(scales, scales.dropFirst()) {
                #expect(
                    earlier.endTime <= later.startTime + 0.001,
                    "scale \(earlier.startTime)–\(earlier.endTime) overlaps \(later.startTime)",
                )
            }
        }
    }

    // ─── Release ─────────────────────────────────────────────────────────────

    /// Opt-in, because a subject that dims on its own schedule is a surprise
    /// nobody asked for.
    @Test("release is off by default")
    func releaseIsOptIn() {
        var document = document()
        let trackID = clip(in: document)
        _ = document.addFilter(PulseFilter.descriptor, to: trackID)

        let withoutRelease = EffectEvaluator().evaluate(document)
        let dips = fades(withoutRelease).filter { command in
            guard case let .fade(start, end) = command.payload else { return false }
            return end < start - 0.001
        }
        #expect(dips.isEmpty, "a default pulse must not touch opacity")
    }

    /// The other half of a beat: something that only grows reads as breathing,
    /// something that also dims reads as being struck.
    @Test("release dims between hits")
    func releaseDims() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.8), for: PulseFilter.Param.release, on: filter.id, in: trackID)

        let dips = fades(EffectEvaluator().evaluate(document)).filter { command in
            guard case let .fade(start, end) = command.payload else { return false }
            return end < start - 0.001
        }
        #expect(!dips.isEmpty, "release must write a falling fade")
    }

    /// Same collision as the scale, same answer.
    @Test("release replaces the sprite's opacity rather than overlapping it")
    func doesNotOverlapFade() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.8), for: PulseFilter.Param.release, on: filter.id, in: trackID)

        for sprite in EffectEvaluator().evaluate(document) {
            let fades = sprite.commands
                .filter { $0.kind == .fade }
                .sorted { $0.startTime < $1.startTime }

            for (earlier, later) in zip(fades, fades.dropFirst()) {
                #expect(
                    earlier.endTime <= later.startTime + 0.001,
                    "fade \(earlier.startTime)–\(earlier.endTime) overlaps \(later.startTime)",
                )
            }
        }
    }

    // ─── Expand ──────────────────────────────────────────────────────────────

    /// A pulse and a shockwave are the same command read backwards.
    ///
    /// A beat hits large and settles back; a wave starts at rest and opens
    /// outward. Written as one flag rather than two filters because everything
    /// else about them is identical.
    @Test("expand grows outward instead of settling back")
    func expandGrowsOutward() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.toggle(true), for: PulseFilter.Param.expand, on: filter.id, in: trackID)
        document.setFilterValue(.number(1), for: PulseFilter.Param.punch, on: filter.id, in: trackID)

        let hits = scales(EffectEvaluator().evaluate(document))
        #expect(!hits.isEmpty)
        for command in hits {
            guard let start = Self.peak(command), let end = Self.rest(command) else { continue }
            #expect(end > start, "a wave must open, got \(start) → \(end)")
        }
    }

    /// Off, it still beats the other way — the flag has to actually reverse it
    /// rather than only ever growing.
    @Test("without expand the hit still settles back")
    func withoutExpandItSettles() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(1), for: PulseFilter.Param.punch, on: filter.id, in: trackID)

        let hits = scales(EffectEvaluator().evaluate(document))
        #expect(!hits.isEmpty)
        for command in hits {
            guard let start = Self.peak(command), let end = Self.rest(command) else { continue }
            #expect(start > end, "a beat must settle, got \(start) → \(end)")
        }
    }

    /// Both directions reach the same size — the punch means the same thing
    /// whichever way it is travelled, so switching the flag does not silently
    /// resize the subject.
    @Test("expand reaches the same extreme as a beat")
    func expandMatchesTheBeatsReach() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(1.5), for: PulseFilter.Param.punch, on: filter.id, in: trackID)

        let evaluator = EffectEvaluator()
        let beating = scales(evaluator.evaluate(document)).compactMap(Self.peak)

        document.setFilterValue(.toggle(true), for: PulseFilter.Param.expand, on: filter.id, in: trackID)
        let waving = scales(evaluator.evaluate(document)).compactMap(Self.rest)

        #expect(!beating.isEmpty)
        #expect(beating.count == waving.count)
        for (beat, wave) in zip(beating, waving) {
            #expect(abs(beat - wave) < 0.01, "beat peaked at \(beat), wave at \(wave)")
        }
    }

    /// A stretched subject stays stretched.
    ///
    /// The pulse reads one number and could write a uniform `_S`, which would
    /// quietly square its subject: an 854×100 bar with a beat on it came back
    /// as a block. Both axes have to survive, in both directions.
    @Test("a stretched sprite keeps its proportions", arguments: [false, true])
    func keepsProportions(expand: Bool) {
        var document = document()
        let trackID = clip(in: document)
        // A bar: wide and short, so a squaring bug cannot hide.
        document.setValue(.number(854), for: ShapeEffect.Param.width, on: document.nodes[0].id)
        document.setValue(.number(100), for: ShapeEffect.Param.height, on: document.nodes[0].id)

        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(1), for: PulseFilter.Param.punch, on: filter.id, in: trackID)
        document.setFilterValue(.toggle(expand), for: PulseFilter.Param.expand, on: filter.id, in: trackID)

        let hits = scales(EffectEvaluator().evaluate(document))
        #expect(!hits.isEmpty)
        for command in hits {
            guard case let .vectorScale(startX, startY, endX, endY) = command.payload else {
                Issue.record("a stretched sprite must keep both axes, got \(command.payload)")
                continue
            }
            // 854 over 100 is the ratio the shape was asked for, and the pulse
            // multiplies rather than replaces — so it holds at both ends.
            #expect(abs(startX / startY - endX / endY) < 0.01)
        }
    }

    /// The curve is the character: a pulse that lands twice is a bounce, one
    /// that rings is elastic. If the choice did not reach the commands they
    /// would all read the same.
    @Test("the fall curve reaches the commands", arguments: PulseFilter.Fall.allCases)
    func fallCurveIsWritten(fall: PulseFilter.Fall) {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(
            .choice(fall.rawValue), for: PulseFilter.Param.bounce, on: filter.id, in: trackID,
        )

        let hits = scales(EffectEvaluator().evaluate(document))
        #expect(!hits.isEmpty)
        for command in hits {
            #expect(command.easing == fall.easing)
        }
    }

    /// Every pulse has to be visible: a hit that never leaves rest is a filter
    /// that appears to do nothing.
    @Test("a hit actually leaves the resting size")
    func hitsAreVisible() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(PulseFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.4), for: PulseFilter.Param.punch, on: filter.id, in: trackID)

        let hits = scales(EffectEvaluator().evaluate(document))
        let peaks = hits.compactMap { command -> Double? in
            guard let peak = Self.peak(command), let rest = Self.rest(command) else { return nil }
            return peak / max(rest, 0.0001)
        }
        #expect(!peaks.isEmpty)
        for ratio in peaks {
            #expect(abs(ratio - 1.4) < 0.01, "expected a 40% kick, got \(ratio)")
        }
    }
}
