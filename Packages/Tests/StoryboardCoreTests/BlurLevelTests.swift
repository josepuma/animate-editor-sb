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

    /// **Superseded, and worth keeping as a record.**
    ///
    /// This used to assert that neighbouring levels *sum* to what one sprite
    /// shows. That premise was wrong and it is what produced the flicker: two
    /// sprites at 0.5 composite to 0.75, not 1.0, so weights that add up
    /// correctly leave the picture dim in the middle of every crossing.
    ///
    /// What actually has to hold is that the **composited** result stays at
    /// one, which `BlurStackTests` checks. Kept here as a pointer, because the
    /// wrong version of this test passed while the bug was on screen.
    @Test("the stack is judged by compositing, not by summing")
    func summingIsTheWrongMeasure() {
        // Two half-opaque layers over one another.
        let a = 0.5, b = 0.5
        #expect(a + b == 1.0)
        #expect(abs((a + b - a * b) - 0.75) < 1e-9)
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

/// The shape most sprites actually have: fade in, hold, fade out.
///
/// The gate multiplies the fades a sprite already carries, so a stretch with no
/// fade command over it has nothing to turn on. A text glyph fades in over
/// 40ms, holds silently for six seconds and fades out — and the radius travels
/// through that silent middle. Reported from a real project: all eleven blur
/// levels invisible, the text staying sharp for the whole clip.
@Suite("Blur over a held sprite")
struct BlurHeldSpriteTests {
    private let evaluator = EffectEvaluator()

    @Test("a blur reaches a sprite that holds its opacity")
    func blurReachesAHeldSprite() throws {
        var document = EffectDocument()
        let node = document.add(TextEffect.descriptor, at: 0, duration: 6000)
        document.setValue(.text("Boy"), for: TextEffect.Param.text, on: node.id)
        document.setValue(.number(40), for: TextEffect.Param.fadeIn, on: node.id)
        document.setValue(.number(200), for: TextEffect.Param.fadeOut, on: node.id)

        let added = document.addFilter(BlurFilter.descriptor, to: node.id)
        let filter = try #require(added)
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 2500, value: 0),
                Keyframe(time: 4800, value: 20),
            ]),
            for: BlurFilter.Param.radius, on: filter.id, in: node.id,
        )

        let sprites = evaluator.evaluate(document)

        /// The blur level actually on top at a moment.
        ///
        /// The **last** visible one in draw order, not the most opaque: levels
        /// the radius has passed are held opaque behind so the stack cannot
        /// thin, so "brightest" now finds the earliest rather than the one
        /// being shown.
        func visibleLevel(at time: Double) -> Double? {
            var top: Double?
            for sprite in sprites {
                let state = StoryboardResolver.resolve(
                    StoryboardResolver.prepare([sprite]), at: time,
                ).first
                guard let state, state.opacity > 0.4 else { continue }
                if case let .blur(radius) = DerivedSprite.parse(sprite.filePath)?.kind {
                    top = radius
                } else {
                    top = 0
                }
            }
            return top
        }

        // Before the ramp the text is sharp; at the last key it is fully blurred.
        #expect(visibleLevel(at: 1000) == 0)
        #expect(visibleLevel(at: 4800) == 20, "the blur never reached its last keyframe")
        // And it stays there past the key, since the value holds.
        #expect(visibleLevel(at: 5700) == 20)
    }
}

/// The stack must never thin out as the radius travels.
///
/// Sprites composite **over** each other, so two at 0.5 do not make one at 1.0
/// — the back is seen through the front and the result is 0.75. Weights that
/// sum to one algebraically therefore darken the picture in the middle of every
/// level crossing: measured, it dipped to 0.76 and returned to 1.00 at each
/// boundary, which reads as flicker.
@Suite("Blur stack stays solid")
struct BlurStackTests {
    private let evaluator = EffectEvaluator()

    /// What the eye receives, compositing in draw order.
    private func visible(_ sprites: [StoryboardSprite], at time: Double) -> Double {
        var result = 0.0
        for sprite in sprites {
            let state = StoryboardResolver.resolve(
                StoryboardResolver.prepare([sprite]), at: time,
            ).first
            let alpha = state?.opacity ?? 0
            guard alpha > 0.001 else { continue }
            result = result + alpha - result * alpha
        }
        return result
    }

    @Test("an animated blur never flickers")
    func stackStaysSolid() throws {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: 2000)
        let added = document.addFilter(BlurFilter.descriptor, to: node.id)
        let filter = try #require(added)
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 2000, value: 20),
            ]),
            for: BlurFilter.Param.radius, on: filter.id, in: node.id,
        )

        let sprites = evaluator.evaluate(document)
        // Every 50ms, which is finer than the level boundaries the dip sat on.
        for time in stride(from: 0.0, through: 2000, by: 50) {
            let light = visible(sprites, at: time)
            // Never *thinner* than solid, which is what reads as flicker.
            // Slightly over is two neighbouring levels overlapping, which the
            // eye cannot see: opacity clamps at one on screen.
            #expect(
                light > 0.98,
                "the stack thinned to \(light) at \(time)ms",
            )
        }
    }

    /// **Superseded.** Holding every passed level opaque was the first answer
    /// to the flicker, and it broke a radius that comes back down: the levels
    /// already left stayed drawn on top, so a run 20 → 0 → 20 never looked
    /// sharp again. Reported from a real project.
    ///
    /// What actually holds is narrower — only the two levels *straddling* the
    /// radius are drawn, the nearer opaque and the further fading in behind.
    @Test("a radius that comes back down looks sharp again")
    func comingBackDownLooksSharp() throws {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: 3000)
        let added = document.addFilter(BlurFilter.descriptor, to: node.id)
        let filter = try #require(added)
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 20),
                Keyframe(time: 1500, value: 0),
                Keyframe(time: 3000, value: 20),
            ]),
            for: BlurFilter.Param.radius, on: filter.id, in: node.id,
        )

        let sprites = evaluator.evaluate(document)

        // Around the trough, not only at its exact bottom.
        //
        // At the bottom the radius equals the lowest level, and an end clamp
        // written `>=` rather than `>` holds the *top* level opaque there while
        // still passing a test that only samples that instant. Sampling either
        // side catches it.
        for time in [1300.0, 1500.0, 1700.0] {
            for sprite in sprites {
                guard case let .blur(radius) = DerivedSprite.parse(sprite.filePath)?.kind,
                      radius > 4
                else { continue }
                let state = StoryboardResolver.resolve(
                    StoryboardResolver.prepare([sprite]), at: time,
                ).first
                #expect(
                    (state?.opacity ?? 0) < 0.05,
                    "blur\(Int(radius)) was drawn at \(time)ms, near the sharp trough",
                )
            }
        }
    }
}
