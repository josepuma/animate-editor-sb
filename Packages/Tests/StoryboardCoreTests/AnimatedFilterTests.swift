import Foundation
import Testing

@testable import StoryboardCore

/// Every filter that declares a parameter animatable has to actually read it
/// per moment.
///
/// A stopwatch beside a value the filter samples once is worse than no
/// stopwatch: the inspector shows the number moving while the picture sits
/// still. Mutation testing found exactly that on a parameter declared and never
/// exercised, so each of these compares an animated run against a held one.
@Suite("Animated filters")
struct AnimatedFilterTests {
    private let evaluator = EffectEvaluator()

    /// A clip that **moves and grows**, which several of these need.
    ///
    /// An animated offset has nothing to change on a still sprite: there is no
    /// movement command for it to displace, only a `defaultX` read once at
    /// birth. Five cases came out identical for exactly that reason — the
    /// subject was wrong, not the filters.
    private func clip(duration: Double = 2000) -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: duration)
        document.setKeyframe(120, for: .x, at: 0, on: node.id)
        document.setKeyframe(520, for: .x, at: duration, on: node.id)
        // No animated scale on the subject.
        //
        // A `_V` from the transform and a `_S` from a filter fight over the
        // same property — osu! picks one at each instant rather than combining
        // them — so an animated wiggle scale was masked by the subject's own.
        // The subject moves, which is what the offsets need, and leaves scale
        // to the filter under test.
        return (document, node.id)
    }

    /// Runs a filter twice — once with `parameter` animated between `from` and
    /// `to`, once held at `from` — and returns both sprite sets.
    private func compare(
        _ descriptor: FilterDescriptor,
        parameter: String,
        from: Double,
        to: Double,
    ) throws -> (animated: [StoryboardSprite], held: [StoryboardSprite]) {
        var document = clip().0
        let nodeID = document.nodes[0].id
        let added = document.addFilter(descriptor, to: nodeID)
        let filter = try #require(added)

        // The held run carries the **same keyframes** with every key at the
        // starting value.
        //
        // Holding a plain value instead compares two differently *cut* outputs,
        // and cutting alone changes the numbers whether or not the factor is
        // read per moment — verified by mutation: freezing the factor left that
        // comparison green. With identical cuts, the only thing that can differ
        // is the factor itself.
        var held = document
        held.setFilterValue(.number(from), for: parameter, on: filter.id, in: nodeID)
        held.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: from),
                Keyframe(time: 700, value: from),
                Keyframe(time: 2000, value: from),
            ]),
            for: parameter, on: filter.id, in: nodeID,
        )

        document.setFilterValue(.number(from), for: parameter, on: filter.id, in: nodeID)
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: from),
                // Deliberately off-centre. With the peak in the middle and a
                // symmetric subject, a filter can write the same multiset of
                // numbers either way and a comparison finds nothing.
                Keyframe(time: 700, value: to),
                Keyframe(time: 2000, value: from),
            ]),
            for: parameter, on: filter.id, in: nodeID,
        )

        return (evaluator.evaluate(document), evaluator.evaluate(held))
    }

    /// Every command in a sprite set, flattened.
    private func signature(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.flatMap { sprite in
            sprite.commands.map { "\($0.kind)|\($0.startTime)|\($0.endTime)|\($0.payload)" }
        }
    }

    /// What the sprites actually look like at one moment.
    ///
    /// The only reading that separates a travelling factor from a frozen one:
    /// cutting changes which commands exist whether or not the factor moves,
    /// but only a factor read per moment changes the *picture* at an instant.
    private func state(of sprites: [StoryboardSprite], at time: Double) -> [String] {
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time)
            .map { s in
                String(
                    format: "%.3f,%.3f,%.3f,%.3f,%.3f,%.0f",
                    s.x, s.y, s.scaleX, s.scaleY, s.opacity, s.rotation * 1000,
                )
            }
            .sorted()
    }

    /// Every number a run writes, sorted.
    ///
    /// Compared instead of the command signature, which measures the *cutting*
    /// — that happens whether or not a factor is read per moment, so a
    /// signature comparison stayed green with the factor frozen at birth.
    /// Rounded, so floating point noise is not mistaken for animation.
    private func numbers(_ sprites: [StoryboardSprite]) -> [Double] {
        var numbers: [Double] = []
        for sprite in sprites {
            for command in sprite.commands {
                switch command.payload {
                case let .fade(a, b): numbers += [a, b]
                case let .scale(a, b): numbers += [a, b]
                case let .moveX(a, b): numbers += [a, b]
                case let .moveY(a, b): numbers += [a, b]
                case let .rotate(a, b): numbers += [a, b]
                case let .move(a, b, c, d): numbers += [a, b, c, d]
                case let .vectorScale(a, b, c, d): numbers += [a, b, c, d]
                case let .color(a, b, c, d, e, f): numbers += [a, b, c, d, e, f]
                case .parameter: break
                }
            }
        }
        return numbers.map { ($0 * 10000).rounded() / 10000 }.sorted()
    }

    @Test(
        "an animated parameter changes what a filter writes",
        arguments: [
            (ShadowFilter.descriptor, ShadowFilter.Param.offsetX, 4.0, 60.0),
            (ShadowFilter.descriptor, ShadowFilter.Param.offsetY, 4.0, 60.0),
            (ShadowFilter.descriptor, ShadowFilter.Param.opacity, 0.2, 0.9),
            (ChromaticFilter.descriptor, ChromaticFilter.Param.offset, 2.0, 30.0),
            (ChromaticFilter.descriptor, ChromaticFilter.Param.angle, 0.0, 90.0),
            (ChromaticFilter.descriptor, ChromaticFilter.Param.intensity, 0.2, 1.0),
            (WiggleFilter.descriptor, WiggleFilter.Param.amount, 2.0, 40.0),
            (WiggleFilter.descriptor, WiggleFilter.Param.rotation, 1.0, 45.0),
            
            (GlowFilter.descriptor, GlowFilter.Param.intensity, 0.2, 1.8),
            (GlowFilter.descriptor, GlowFilter.Param.size, 1.0, 4.0),
        ],
    )
    func animatedParameterChangesOutput(
        descriptor: FilterDescriptor, parameter: String, from: Double, to: Double,
    ) throws {
        let (animated, held) = try compare(
            descriptor, parameter: parameter, from: from, to: to,
        )
        #expect(!animated.isEmpty, "\(descriptor.name) produced nothing")

        // Compared by the **range of values** each run reaches, not by the
        // shape of its command list.
        //
        // Comparing signatures measures the *cutting*, which happens whether or
        // not the factor is read per moment — verified by mutation: freezing
        // the factor at the sprite's birth left a signature comparison green.
        // A factor that actually travels makes the output reach values the held
        // run never does.
        // Compared as **resolved sprite state at the peak**, not as the list of
        // numbers written.
        //
        // Comparing written numbers measures the cutting as much as the factor:
        // cutting alone changes them, so a frozen factor slipped through —
        // verified by mutation twice. What only a factor read per moment can do
        // is put the picture in a different state at a given instant.
        // Several moments, not one: a wobble is seeded per step, so a single
        // instant can land where both runs happen to agree. A factor that
        // travels has to separate them *somewhere* across the clip.
        // Compared **at the peak specifically**, not "somewhere".
        //
        // Sampling for any difference lets a case pass on a difference some
        // *other* parameter produced — Shadow and Chromatic both escaped a
        // frozen-opacity mutation that way, because their offsets were moving
        // in the same run. At 700ms the animated run is at `to` and the held
        // one at `from`, so a difference there is this parameter's or nothing.
        let differs = state(of: animated, at: 700) != state(of: held, at: 700)
        #expect(
            differs,
            """
            \(descriptor.name) · \(parameter) is declared animatable but the \
            picture is identical to holding it still at every moment sampled
            """,
        )
    }

    /// The other half: a filter nobody animates must produce exactly what it
    /// did before any of this existed. These land in finished projects, and a
    /// default that changed the output would rewrite approved work.
    @Test(
        "an unanimated filter is unchanged",
        arguments: [
            ShadowFilter.descriptor, ChromaticFilter.descriptor,
            WiggleFilter.descriptor, GlowFilter.descriptor, BlurFilter.descriptor,
        ],
    )
    func unanimatedIsUnchanged(descriptor: FilterDescriptor) throws {
        var document = clip().0
        let nodeID = document.nodes[0].id
        let added = document.addFilter(descriptor, to: nodeID)
        _ = try #require(added)

        let first = signature(evaluator.evaluate(document))
        let second = signature(evaluator.evaluate(document))
        #expect(first == second, "\(descriptor.name) is not deterministic")
        #expect(!first.isEmpty)
    }

    /// Wiggle's scale gets its own case, because it cannot be tested on a
    /// `Shape`.
    ///
    /// A shape writes a `_V` to say how big it is; the wiggle writes an `_S`.
    /// osu! has no way to combine two commands driving the same property — it
    /// picks one at each instant — so the shape's own size wins and the wobble
    /// is invisible. That is a limit of the format rather than a defect in the
    /// animation, and it is worth a test saying so.
    @Test("an animated wiggle scale reaches a subject with no size of its own")
    func wiggleScaleAnimates() throws {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(3), for: EmitterEffect.Param.count, on: node.id)
        document.setValue(.number(2000), for: EmitterEffect.Param.life, on: node.id)

        let added = document.addFilter(WiggleFilter.descriptor, to: node.id)
        let filter = try #require(added)

        var held = document
        for (doc, peak) in [(0, 0.05), (1, 0.6)] {
            let track = KeyframeTrack([
                Keyframe(time: 0, value: 0.05),
                Keyframe(time: 700, value: peak),
                Keyframe(time: 2000, value: 0.05),
            ])
            if doc == 0 {
                held.setFilterAnimation(
                    track, for: WiggleFilter.Param.scale, on: filter.id, in: node.id,
                )
            } else {
                document.setFilterAnimation(
                    track, for: WiggleFilter.Param.scale, on: filter.id, in: node.id,
                )
            }
        }

        let moments = stride(from: 200.0, through: 1800.0, by: 200.0)
        let differs = moments.contains { time in
            state(of: evaluator.evaluate(document), at: time)
                != state(of: evaluator.evaluate(held), at: time)
        }
        #expect(differs, "an animated wiggle scale did not reach the picture")
    }

    /// A parameter whose animation rests at zero still has to draw wherever its
    /// keys take it — the guard that skips a filter cannot read the resting
    /// value alone.
    @Test("a filter animated up from zero still draws")
    func zeroRestingStillDraws() throws {
        var document = clip().0
        let nodeID = document.nodes[0].id
        let added = document.addFilter(ShadowFilter.descriptor, to: nodeID)
        let filter = try #require(added)

        document.setFilterValue(
            .number(0), for: ShadowFilter.Param.opacity, on: filter.id, in: nodeID,
        )
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 2000, value: 0.8),
            ]),
            for: ShadowFilter.Param.opacity, on: filter.id, in: nodeID,
        )

        let shadows = evaluator.evaluate(document).filter { $0.id.contains("shadow") }
        #expect(!shadows.isEmpty, "an animated opacity resting at zero drew nothing")
    }
}

/// Every animated filter, on the shape of sprite that broke Blur.
///
/// A text glyph fades in over 40ms, holds silently for seconds, and fades out —
/// and it never moves, so its position lives in `defaultX/Y` read once. Both of
/// those are holes a filter can fall into: what it multiplies or displaces has
/// to *exist* before it can be animated.
///
/// Blur was reported broken this way from a real project. Asking the same
/// question of every other filter found two more — Shadow's offset and
/// Chromatic's split, both frozen at their first value — which is why this is a
/// parametric suite rather than a fix in one place.
@Suite("Animated filters on a held, still sprite")
struct HeldSpriteFilterTests {
    private let evaluator = EffectEvaluator()

    private func heldClip() -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        let node = document.add(TextEffect.descriptor, at: 0, duration: 6000)
        document.setValue(.text("Boy"), for: TextEffect.Param.text, on: node.id)
        document.setValue(.number(40), for: TextEffect.Param.fadeIn, on: node.id)
        document.setValue(.number(200), for: TextEffect.Param.fadeOut, on: node.id)
        return (document, node.id)
    }

    /// Every sprite's resolved state at one moment, compared per sprite so an
    /// untouched subject cannot swamp the difference.
    private func state(_ document: EffectDocument, at time: Double) -> [String] {
        evaluator.evaluate(document).map { sprite in
            let s = StoryboardResolver.resolve(
                StoryboardResolver.prepare([sprite]), at: time,
            ).first
            return String(
                format: "%.2f,%.2f,%.2f,%.2f",
                s?.x ?? 0, s?.y ?? 0, s?.scaleX ?? 0, s?.opacity ?? 0,
            )
        }.sorted()
    }

    @Test(
        "an animated parameter reaches a sprite that holds still",
        arguments: [
            (GlowFilter.descriptor, GlowFilter.Param.intensity, 0.1, 2.0),
            (GlowFilter.descriptor, GlowFilter.Param.size, 1.0, 5.0),
            (ShadowFilter.descriptor, ShadowFilter.Param.opacity, 0.1, 1.0),
            (ShadowFilter.descriptor, ShadowFilter.Param.offsetX, 0.0, 80.0),
            (ShadowFilter.descriptor, ShadowFilter.Param.offsetY, 0.0, 80.0),
            (ChromaticFilter.descriptor, ChromaticFilter.Param.intensity, 0.1, 1.0),
            (ChromaticFilter.descriptor, ChromaticFilter.Param.offset, 0.0, 30.0),
            (WiggleFilter.descriptor, WiggleFilter.Param.amount, 0.0, 40.0),
            (BlurFilter.descriptor, BlurFilter.Param.radius, 0.0, 20.0),
        ],
    )
    func reachesAHeldSprite(
        descriptor: FilterDescriptor, parameter: String, from: Double, to: Double,
    ) throws {
        var (document, nodeID) = heldClip()
        let added = document.addFilter(descriptor, to: nodeID)
        let filter = try #require(added)
        document.setFilterValue(.number(from), for: parameter, on: filter.id, in: nodeID)

        var held = document
        held.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: from),
                Keyframe(time: 4800, value: from),
            ]),
            for: parameter, on: filter.id, in: nodeID,
        )
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: from),
                Keyframe(time: 4800, value: to),
            ]),
            for: parameter, on: filter.id, in: nodeID,
        )

        // Deep in the silent middle, where the sprite has neither a fade
        // command nor a movement of its own.
        #expect(
            state(document, at: 4700) != state(held, at: 4700),
            """
            \(descriptor.name) · \(parameter) never reached a sprite that holds \
            its opacity and does not move
            """,
        )
    }
}
