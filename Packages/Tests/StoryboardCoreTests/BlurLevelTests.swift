import Foundation
import Testing

@testable import StoryboardCore

/// Animating a blur radius.
///
/// The expensive kind of keyframe, and the only one in the library. A radius
/// names a texture rather than landing in a command, and osu! draws one image
/// for a sprite's whole life — so a blur that changes is not one sprite
/// changing, it is one sprite per level.
@Suite("Blur levels")
struct BlurLevelTests {
    private let evaluator = EffectEvaluator()

    private func document(duration: Double = 2000) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: duration)
        document.setValue(.integer(2), for: EmitterEffect.Param.count, on: node.id)
        document.setValue(.number(duration), for: EmitterEffect.Param.life, on: node.id)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    /// Builds a blur whose radius travels from `from` to `to`.
    private func animated(
        from: Double, to: Double, duration: Double = 2000,
    ) throws -> (EffectDocument, EffectNode.ID, FilterNode) {
        var document = document(duration: duration)
        let trackID = clip(in: document)
        let added = document.addFilter(BlurFilter.descriptor, to: trackID)
        let filter = try #require(added)

        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: from),
                Keyframe(time: duration, value: to),
            ]),
            for: BlurFilter.Param.radius, on: filter.id, in: trackID,
        )
        return (document, trackID, filter)
    }

    // ─── Counting the cost ───────────────────────────────────────────────────

    /// Only the levels actually crossed, at the quantisation the radius is
    /// already subject to. This is what makes the price knowable before the
    /// file is written.
    @Test("a run crosses one level per quantum step")
    func levelsAreCounted() {
        // 0 to 10 at a step of 2: 0, 2, 4, 6, 8, 10.
        #expect(DerivedSprite.levels(from: 0, to: 10) == [0, 2, 4, 6, 8, 10])
        // Order does not matter — a radius that falls crosses the same images.
        #expect(DerivedSprite.levels(from: 10, to: 0) == [0, 2, 4, 6, 8, 10])
        // A still radius is one level, never zero.
        #expect(DerivedSprite.levels(from: 8, to: 8) == [8])
    }

    /// The multiplier has to answer for how far the value travels, which is
    /// unlike every other filter in the library — theirs depend on a count
    /// somebody typed.
    @Test("the multiplier reports one sprite per level")
    func multiplierCountsLevels() throws {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: 0),
            Keyframe(time: 1000, value: 10),
        ])
        let node = FilterNode(
            id: "b", type: "blur",
            animations: [BlurFilter.Param.radius: track],
        )
        let context = FilterContext(descriptor: BlurFilter.descriptor, node: node)

        #expect(BlurFilter().estimatedMultiplier(in: context) == 6)
    }

    /// Still, it is the only filter that adds nothing at all — that is the
    /// whole point of it, and animating must not quietly take it away from
    /// everyone who never touched a stopwatch.
    @Test("an unanimated blur is still one sprite in, one out")
    func stillBlurCostsNothing() {
        let node = FilterNode(
            id: "b", type: "blur",
            values: [BlurFilter.Param.radius: .number(8)],
        )
        let context = FilterContext(descriptor: BlurFilter.descriptor, node: node)
        #expect(BlurFilter().estimatedMultiplier(in: context) == 1)

        let unfiltered = document()
        var filtered = unfiltered
        let trackID = clip(in: filtered)
        _ = filtered.addFilter(BlurFilter.descriptor, to: trackID)

        #expect(
            evaluator.evaluate(filtered).count == evaluator.evaluate(unfiltered).count,
        )
    }

    // ─── What the sprites actually say ───────────────────────────────────────

    /// Each copy holds one fixed level, because a sprite draws one image for
    /// its whole life. Two copies naming the same texture would be one image
    /// drawn twice, which is a brightness bug rather than an animation.
    @Test("an animated radius produces one sprite per distinct texture")
    func spritesCoverEveryLevel() throws {
        let (document, _, _) = try animated(from: 0, to: 6)
        let sprites = evaluator.evaluate(document)

        // Two particles × four levels (0, 2, 4, 6).
        let paths = Set(sprites.map(\.filePath))
        #expect(paths.count == 4)

        // And every one of them is a real blur level, not a mix.
        let radii = paths.compactMap { path -> Double? in
            guard case let .blur(radius) = DerivedSprite.parse(path)?.kind else {
                // The unblurred level keeps the source path.
                return 0
            }
            return radius
        }
        #expect(Set(radii) == [0, 2, 4, 6])
    }

    /// **The one that matters.** A level has to be visible while the radius is
    /// near it and invisible otherwise — that is the entire mechanism. Without
    /// the gate every level draws at once, which is not a growing blur but all
    /// of them stacked at every instant.
    @Test("each level is only visible while the radius is near it")
    func levelsAreGated() throws {
        let (document, _, _) = try animated(from: 0, to: 8)
        let sprites = evaluator.evaluate(document)

        func opacity(_ sprite: StoryboardSprite, at time: Double) -> Double {
            var value = 0.0
            for command in sprite.commands.sorted(by: { $0.startTime < $1.startTime }) {
                guard case let .fade(start, end) = command.payload else { continue }
                if time < command.startTime { break }
                if time >= command.endTime { value = end; continue }
                let span = command.endTime - command.startTime
                let t = span > 0 ? (time - command.startTime) / span : 0
                value = start + (end - start) * t
            }
            return value
        }

        func level(of sprite: StoryboardSprite) -> Double {
            guard case let .blur(radius) = DerivedSprite.parse(sprite.filePath)?.kind
            else { return 0 }
            return radius
        }

        // Early in the clip the radius is near 0, so the sharpest level leads
        // and the softest must be dark.
        let early = sprites.map { (level(of: $0), opacity($0, at: 100)) }
        let sharpEarly = early.filter { $0.0 == 0 }.map(\.1).max() ?? 0
        let softEarly = early.filter { $0.0 == 8 }.map(\.1).max() ?? 0
        #expect(sharpEarly > softEarly)

        // Late it is the other way round.
        let late = sprites.map { (level(of: $0), opacity($0, at: 1900)) }
        let sharpLate = late.filter { $0.0 == 0 }.map(\.1).max() ?? 0
        let softLate = late.filter { $0.0 == 8 }.map(\.1).max() ?? 0
        #expect(softLate > sharpLate)
    }

    /// Neighbouring levels must sum to roughly what one sprite would show, or
    /// the stack dips in brightness halfway between every pair — a pulsing
    /// blur rather than a smooth one.
    ///
    /// This is the reason the weights are linear across exactly one step: any
    /// other falloff leaves a hole or a bulge at the crossing point.
    @Test("neighbouring levels sum to one across a crossing")
    func crossFadesSumToOne() throws {
        let (document, _, _) = try animated(from: 0, to: 8)
        let sprites = evaluator.evaluate(document)

        // Read out of the evaluated sprites, never recomputed from the same
        // rule the filter uses. A test that reimplements its subject's formula
        // agrees with any formula — verified by mutation: an earlier version of
        // this passed with the gate forced to full, which draws every level at
        // once and is the exact bug the cross-fade prevents.
        func opacity(_ sprite: StoryboardSprite, at time: Double) -> Double {
            var value = 0.0
            for command in sprite.commands.sorted(by: { $0.startTime < $1.startTime }) {
                guard case let .fade(start, end) = command.payload else { continue }
                if time < command.startTime { break }
                if time >= command.endTime { value = end; continue }
                let span = command.endTime - command.startTime
                let t = span > 0 ? (time - command.startTime) / span : 0
                value = start + (end - start) * t
            }
            return value
        }

        // One particle's stack, so the sum is over levels rather than over
        // every particle alive at once.
        let byParticle = Dictionary(grouping: sprites) { sprite in
            sprite.id.split(separator: "l").dropLast().joined(separator: "l")
        }
        let stack = try #require(byParticle.values.max { $0.count < $1.count })
        #expect(stack.count > 1, "an animated radius must produce a stack")

        // The subject's own fade at the same moment, so the comparison is
        // against how bright one unfiltered sprite would be.
        var unblurred = document
        let trackID = clip(in: unblurred)
        unblurred.nodes.first.map { node in
            for filter in node.filters { unblurred.removeFilter(filter.id, from: trackID) }
        }
        let plain = evaluator.evaluate(unblurred)
        let subject = try #require(plain.first)

        for percent in stride(from: 0.15, through: 0.85, by: 0.1) {
            let time = 2000 * percent
            let total = stack.reduce(0.0) { $0 + opacity($1, at: time) }
            let expected = opacity(subject, at: time)
            #expect(
                abs(total - expected) < 0.05,
                "at \(time)ms the stack summed to \(total), one sprite shows \(expected)",
            )
        }
    }

    /// A particle born late must show the radius in force *then*. Reading the
    /// clip's own start would give every particle the same level however long
    /// after the clip began it appeared.
    @Test("a sprite's levels come from its own life, not the clip's start")
    func levelsFollowTheSpriteNotTheClip() throws {
        var document = document(duration: 4000)
        let trackID = clip(in: document)
        // Emit over the whole clip, so particles are born at different times.
        document.setValue(.integer(8), for: EmitterEffect.Param.count, on: trackID)
        document.setValue(.number(500), for: EmitterEffect.Param.life, on: trackID)

        let added = document.addFilter(BlurFilter.descriptor, to: trackID)
        let filter = try #require(added)
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 4000, value: 20),
            ]),
            for: BlurFilter.Param.radius, on: filter.id, in: trackID,
        )

        let sprites = evaluator.evaluate(document)
        // Sprites born at different times must not all carry the same texture:
        // if they did, the radius was read once for the clip rather than per
        // sprite.
        #expect(Set(sprites.map(\.filePath)).count > 1)
    }

    /// A radius resting at zero with no animation still means "no blur", and
    /// must come back untouched — the guard that keeps the filter free for
    /// anyone who has it switched effectively off.
    @Test("a zero radius leaves the sprites alone")
    func zeroRadiusIsInert() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)
        document.setFilterValue(
            .number(0), for: BlurFilter.Param.radius,
            on: filter!.id, in: trackID,
        )

        let filtered = evaluator.evaluate(document)
        #expect(filtered.allSatisfy { !DerivedSprite.isDerived($0.filePath) })
    }
}
