import Foundation
import Testing

@testable import StoryboardCore

/// Keyframing a filter parameter.
///
/// The value of these is almost entirely in what they forbid. A filter reads
/// its parameters once and applies them as a factor over sprites it was
/// reshaping anyway — which is correct while the value is still and is exactly
/// the bug this project has already shipped twice, with opacity and with scale
/// on `GroupTransform`:
///
/// > A property that animates needs commands of its own, not a factor.
///
/// So the tests that matter are not "the number arrives" but "the number keeps
/// moving after the sprite is born".
@Suite("Filter keyframes")
struct FilterKeyframeTests {
    private let evaluator = EffectEvaluator()

    /// One emitter on one track, matching how the other filter suites build
    /// their subject — particles carry the fade and scale commands a glow rides
    /// on, which is what these tests need to see move.
    private func document(duration: Double = 2000) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: duration)
        document.setValue(.integer(4), for: EmitterEffect.Param.count, on: node.id)
        // Particles that live the whole clip, so a keyframe late in it falls
        // inside a command rather than after every sprite has died.
        document.setValue(.number(duration), for: EmitterEffect.Param.life, on: node.id)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    // ─── The contract that lets fifteen filters stay untouched ───────────────

    /// A parameter says whether it can be animated, so the inspector learns one
    /// general rule instead of one rule per filter. Most say no: a stopwatch on
    /// a structural value promises something the format cannot deliver.
    @Test("a parameter declares whether it animates")
    func parameterDeclaresAnimation() {
        let intensity = GlowFilter.descriptor.parameter(GlowFilter.Param.intensity)
        #expect(intensity?.animation == .commands)

        // Softness lands in a texture path, not a command — animating it is a
        // sprite per level, which is a different capability and a different
        // cost. Stage 2, deliberately not this.
        let softness = GlowFilter.descriptor.parameter(GlowFilter.Param.radius)
        #expect(softness?.animation == EffectParameter.Animation.none)
    }

    /// Reading a value with a time when nothing animates it has to give exactly
    /// what reading it without one gives. Every filter now asks with a time
    /// unconditionally, so if these disagreed the whole library would change
    /// behaviour for projects that never touched a stopwatch.
    @Test("an unanimated parameter reads the same with or without a time")
    func restingValueUnchanged() {
        let node = FilterNode(
            id: "f", type: "glow",
            values: [GlowFilter.Param.intensity: .number(0.6)],
        )
        let context = FilterContext(descriptor: GlowFilter.descriptor, node: node)

        #expect(context.number(GlowFilter.Param.intensity) == 0.6)
        #expect(context.number(GlowFilter.Param.intensity, at: 0) == 0.6)
        #expect(context.number(GlowFilter.Param.intensity, at: 1500) == 0.6)
    }

    /// The value moves between its keys, with the easing of the key it leaves.
    @Test("an animated parameter travels between its keys")
    func animatedValueTravels() {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: 0),
            Keyframe(time: 1000, value: 1),
        ])
        let node = FilterNode(
            id: "f", type: "glow",
            animations: [GlowFilter.Param.intensity: track],
        )
        let context = FilterContext(descriptor: GlowFilter.descriptor, node: node)

        #expect(context.number(GlowFilter.Param.intensity, at: 0) == 0)
        #expect(abs(context.number(GlowFilter.Param.intensity, at: 500) - 0.5) < 1e-9)
        #expect(context.number(GlowFilter.Param.intensity, at: 1000) == 1)
    }

    /// A track switched off falls back to the resting value, exactly as if it
    /// had no keys — the stopwatch turns animation off without destroying it.
    @Test("a disabled track falls back to the resting value")
    func disabledTrackIsInert() {
        let track = KeyframeTrack(
            [Keyframe(time: 0, value: 0), Keyframe(time: 1000, value: 2)],
            isEnabled: false,
        )
        let node = FilterNode(
            id: "f", type: "glow",
            values: [GlowFilter.Param.intensity: .number(0.5)],
            animations: [GlowFilter.Param.intensity: track],
        )
        let context = FilterContext(descriptor: GlowFilter.descriptor, node: node)

        #expect(context.number(GlowFilter.Param.intensity, at: 500) == 0.5)
        #expect(!context.isAnimated(GlowFilter.Param.intensity))
    }

    /// A key dragged past what the field accepts would otherwise write a value
    /// the very same parameter refuses when typed beside it.
    @Test("keyframe values are clamped to the parameter's range")
    func keyframesAreClamped() {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: -5),
            Keyframe(time: 1000, value: 99),
        ])
        let node = FilterNode(
            id: "f", type: "glow",
            animations: [GlowFilter.Param.intensity: track],
        )
        let context = FilterContext(descriptor: GlowFilter.descriptor, node: node)

        // Intensity is 0...2.
        #expect(context.number(GlowFilter.Param.intensity, at: 0) == 0)
        #expect(context.number(GlowFilter.Param.intensity, at: 1000) == 2)
    }

    // ─── The bug this exists to prevent ──────────────────────────────────────

    /// **The one that matters.** A halo whose intensity climbs must actually be
    /// dimmer early and brighter late. Sampled once — the obvious and wrong
    /// implementation — every command would carry whatever the factor was when
    /// the sprite was born, and the halo would sit frozen while the inspector
    /// showed the number moving.
    @Test("an animated intensity does not freeze at its first value")
    func animatedIntensityDoesNotFreeze() throws {
        var document = document()
        let trackID = clip(in: document)
        let added = document.addFilter(GlowFilter.descriptor, to: trackID)
        let filter = try #require(added)

        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0.1),
                Keyframe(time: 2000, value: 2.0),
            ]),
            for: GlowFilter.Param.intensity,
            on: filter.id,
            in: trackID,
        )

        // The same clip with the intensity held at the animation's first value.
        // Comparing against this rather than reading one halo's numbers is what
        // makes the assertion mean something: a particle's own fade-out drops
        // to zero at death whatever the filter does, so "the last opacity is
        // higher" would be testing the emitter, not the factor.
        var frozen = document
        frozen.setFilterAnimation(nil, for: GlowFilter.Param.intensity, on: filter.id, in: trackID)
        frozen.setFilterValue(
            .number(0.1), for: GlowFilter.Param.intensity, on: filter.id, in: trackID,
        )

        let animatedHalos = evaluator.evaluate(document).filter { $0.id.contains("/g") }
        let frozenHalos = evaluator.evaluate(frozen).filter { $0.id.contains("/g") }
        let animated = try #require(animatedHalos.first)
        let held = try #require(frozenHalos.first)

        // Compared *within* one command, not across the sprite's list.
        //
        // Reading the brightest value anywhere would pass even with the factor
        // frozen, because cutting at keyframes alone makes later pieces carry
        // later values — that measures the cut, not the factor. Verified by
        // mutation: freezing the end sample left an earlier version of this
        // test green.
        //
        // What only a travelling factor can produce is a *single* command whose
        // two ends were multiplied by different numbers, so the halo's ratio to
        // its subject changes across that one command.
        // Each halo compared against the *held* version of itself, matched by
        // span. The two are cut identically only where nothing animates, so the
        // held sprite is read by sampling its own fade at the same moments.
        func factors(_ sprite: StoryboardSprite) -> [(Double, Double, Double, Double)] {
            sprite.commands.compactMap { command in
                guard case let .fade(start, end) = command.payload,
                      command.endTime > command.startTime,
                      // Clamping hides any difference once a product reaches 1.
                      start < 0.99, end < 0.99
                else { return nil }
                return (command.startTime, command.endTime, start, end)
            }
        }

        let animatedFades = factors(animated)
        let heldFades = factors(held)
        #expect(!animatedFades.isEmpty, "no usable fade command was produced")
        #expect(!heldFades.isEmpty)

        // The animated halo must be brighter late in the clip than the held one
        // ever gets, because 0.1 never climbs while the animation reaches 2.0.
        // The brightest the held halo ever reaches is its resting 0.1, because
        // a still factor cannot climb. The animated one has to exceed that: its
        // intensity travels to 2.0, so both its fade-in and the start of its
        // fade-out carry far more light.
        let heldPeak = heldFades.flatMap { [$0.2, $0.3] }.max() ?? 0
        let animatedPeak = animatedFades.flatMap { [$0.2, $0.3] }.max() ?? 0
        #expect(animatedPeak > heldPeak * 2)

        // And — the assertion that actually pins the bug.
        //
        // Every reading above can be produced without the factor travelling,
        // because cutting at keyframes alone makes later pieces carry later
        // values. Verified by mutation: freezing an end sample left them green.
        //
        // What only a travelling factor changes is the *shape* of a single
        // command. Two runs whose keyframes differ only in the middle produce
        // identical cut points and identical end values — so any difference in
        // what a command carries at its far end can only come from the factor
        // being read there.
        //
        // The key has to fall *inside* a command for this to test anything: a
        // particle's fade-in is a few hundred milliseconds long, so a key at
        // 1000 lands in the gap between commands and cutting becomes a no-op.
        // The mid key here sits inside the fade-in deliberately.
        var bowed = document
        bowed.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0.1),
                // Same ends, a different route between them.
                Keyframe(time: 150, value: 2.0),
                Keyframe(time: 2000, value: 2.0),
            ]),
            for: GlowFilter.Param.intensity, on: filter.id, in: trackID,
        )
        let bowedHalos = evaluator.evaluate(bowed).filter { $0.id.contains("/g") }
        let bowedFades = factors(try #require(bowedHalos.first))

        // Compared as whole command lists, not just end values: cutting is
        // what lets a mid-clip key change anything at all, so the count and the
        // shape both have to move.
        // Both runs must produce comparable commands before their difference
        // means anything: an empty list satisfies `!=` against a full one, and
        // an earlier version of this test passed every mutation for exactly
        // that reason.
        #expect(bowedFades.count == animatedFades.count)
        #expect(!bowedFades.isEmpty)

        // The bowed run reaches 2.0 by 150ms, so the piece ending there must
        // carry roughly twenty times what the same piece carries when the
        // factor is read only at the sprite's birth (0.1).
        //
        // Comparing the two *shapes* is not enough and an earlier version of
        // this test made exactly that mistake: cutting alone already makes the
        // lists differ, so "they are not equal" stayed true with the factor
        // frozen. What only a factor read at the piece's own end can produce is
        // the right *magnitude* there.
        let bowedFirst = try #require(bowedFades.first)
        let plainFirst = try #require(animatedFades.first)
        #expect(bowedFirst.3 > plainFirst.3 * 1.5)
        #expect(
            bowedFirst.3 > 0.5,
            "a factor frozen at birth would leave this near the resting 0.1",
        )
    }

    /// Size is the glow's other animatable parameter, and it rides the scale
    /// commands rather than the fades. Declared animatable without a test, a
    /// filter reading it at rest would pass every other case here — found by
    /// mutation, which is the only way an untested parameter shows up.
    @Test("an animated size reaches the halo's scale commands")
    func animatedSizeTravels() throws {
        var document = document()
        let trackID = clip(in: document)
        let added = document.addFilter(GlowFilter.descriptor, to: trackID)
        let filter = try #require(added)

        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 1),
                Keyframe(time: 150, value: 6),
                Keyframe(time: 2000, value: 6),
            ]),
            for: GlowFilter.Param.size, on: filter.id, in: trackID,
        )

        var held = document
        held.setFilterAnimation(nil, for: GlowFilter.Param.size, on: filter.id, in: trackID)
        held.setFilterValue(.number(1), for: GlowFilter.Param.size, on: filter.id, in: trackID)

        func peakScale(_ sprites: [StoryboardSprite]) -> Double {
            sprites.filter { $0.id.contains("/g") }.flatMap(\.commands).compactMap { command in
                switch command.payload {
                case let .scale(start, end): max(start, end)
                case let .vectorScale(_, startY, _, endY): max(startY, endY)
                default: nil
                }
            }.max() ?? 0
        }

        let animated = peakScale(evaluator.evaluate(document))
        let still = peakScale(evaluator.evaluate(held))
        #expect(animated > still * 2, "an animated size must grow the halo")
    }

    /// A keyframe falling inside a command has to cut it, or the key's curve is
    /// lost inside a span the underlying command drew — the same rule position
    /// and scale already follow.
    @Test("a command spanning a keyframe is cut at it")
    func commandsAreCutAtKeys() {
        let command = Command(
            easing: .linear, startTime: 0, endTime: 1000,
            payload: .fade(start: 0, end: 1),
        )
        let pieces = AnimatedFactor.split(command, at: [250, 750])

        #expect(pieces.count == 3)
        #expect(pieces.map(\.startTime) == [0, 250, 750])
        #expect(pieces.map(\.endTime) == [250, 750, 1000])

        // The pieces sample the original, so the value at each cut is what the
        // original held there.
        guard case let .fade(_, end) = pieces[0].payload else {
            Issue.record("expected a fade")
            return
        }
        #expect(abs(end - 0.25) < 1e-9)
    }

    /// A key exactly on a boundary already is one. Cutting there would leave a
    /// zero-length command, which reads as an instant set rather than as part
    /// of the interpolation it came from.
    @Test("a key on a command's own boundary does not cut it")
    func boundaryKeyDoesNotCut() {
        let command = Command(
            easing: .linear, startTime: 0, endTime: 1000,
            payload: .fade(start: 0, end: 1),
        )
        #expect(AnimatedFactor.split(command, at: [0, 1000]).count == 1)
    }

    /// Nobody animating means nothing is cut: the commands come back one for
    /// one. Without this every project that never touched a stopwatch would
    /// start paying for keyframes it does not have.
    @Test("no keyframes means no extra commands")
    func noKeysNoCost() throws {
        var plain = document()
        let plainTrack = clip(in: plain)
        _ = plain.addFilter(GlowFilter.descriptor, to: plainTrack)

        let sprites = evaluator.evaluate(plain)
        let halos = sprites.filter { $0.id.contains("/g") }
        let subjects = sprites.filter { !$0.id.contains("/g") }
        let halo = try #require(halos.first)
        let subject = try #require(subjects.first)

        // The halo mirrors its subject's commands, plus at most the implied
        // scale a sprite without one needs.
        #expect(halo.commands.count <= subject.commands.count + 1)
    }

    /// An intensity animated up from zero still draws a halo wherever its keys
    /// take it, so the estimate has to answer for the whole track rather than
    /// for one instant of it. Read at rest, this would report ×1 and lie.
    @Test("the multiplier counts an animated intensity resting at zero")
    func multiplierSeesAnimation() {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: 0),
            Keyframe(time: 1000, value: 1.5),
        ])
        let node = FilterNode(
            id: "f", type: "glow",
            values: [GlowFilter.Param.intensity: .number(0)],
            animations: [GlowFilter.Param.intensity: track],
        )
        let context = FilterContext(descriptor: GlowFilter.descriptor, node: node)

        #expect(GlowFilter().estimatedMultiplier(in: context) == 2)
    }

    // ─── Persistence ─────────────────────────────────────────────────────────

    /// A project saved before `animations` existed has no such key, and
    /// synthesised decoding treats a missing non-optional as a failure — the
    /// whole file would refuse to open rather than open without animation. The
    /// same trap `"scale"` fell into when it became two axes.
    @Test("a filter saved before keyframes existed still decodes")
    func decodesWithoutAnimations() throws {
        let json = #"""
        {"id":"glow-1","type":"glow","isEnabled":true,"values":{}}
        """#
        let node = try JSONDecoder().decode(FilterNode.self, from: Data(json.utf8))

        #expect(node.id == "glow-1")
        #expect(node.animations.isEmpty)
    }

    /// A copied filter needs its own identity — the id prefixes the sprites it
    /// derives — and it has to carry its keyframes, or the copy is of something
    /// else.
    @Test("a copied filter keeps its keyframes and gains a new id")
    func copyCarriesAnimations() {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: 0.2),
            Keyframe(time: 500, value: 1),
        ])
        let node = FilterNode(
            id: "glow-1", type: "glow",
            animations: [GlowFilter.Param.intensity: track],
        )
        let copy = node.reidentified()

        #expect(copy.id != node.id)
        #expect(copy.animations == node.animations)
    }
}

/// A filter must not straighten the curves it is only passing along.
///
/// Cutting a command re-expresses its curve as a row of chords, which is right
/// for a command whose values are about to be rewritten and wrong for one the
/// filter merely copies. A glow takes its subject's movement verbatim, so
/// slicing an eased `_M` left the halo travelling in straight lines while the
/// sprite followed the curve — measured at 30px apart, meeting again at every
/// cut, which is exactly what a chord approximating an arc looks like.
@Suite("Filters preserve untouched curves")
struct FilterCurvePreservationTests {
    private let evaluator = EffectEvaluator()

    @Test("a halo follows an eased move exactly")
    func haloFollowsTheCurve() throws {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: 2000)
        document.setKeyframe(100, for: .x, at: 0, easing: .quadOut, on: node.id)
        document.setKeyframe(600, for: .x, at: 2000, on: node.id)

        let added = document.addFilter(GlowFilter.descriptor, to: node.id)
        let filter = try #require(added)
        // An animated factor is what introduces the cuts in the first place.
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0.2),
                Keyframe(time: 1000, value: 1.5),
                Keyframe(time: 2000, value: 0.3),
            ]),
            for: GlowFilter.Param.intensity, on: filter.id, in: node.id,
        )

        let sprites = evaluator.evaluate(document)
        let halos = sprites.filter { $0.id.contains("/g") }
        let subjects = sprites.filter { !$0.id.contains("/g") }
        let halo = try #require(halos.first)
        let subject = try #require(subjects.first)

        func x(_ sprite: StoryboardSprite, at time: Double) -> Double {
            StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time)
                .first?.x ?? .nan
        }

        // Sampled between the cuts, which is where a chord departs from its arc
        // — at the cuts themselves the two agree even when the bug is present.
        for time in stride(from: 0.0, through: 2000, by: 100) {
            #expect(
                abs(x(subject, at: time) - x(halo, at: time)) < 0.01,
                "halo drifted from its subject at \(time)ms",
            )
        }
    }

    /// The rewritten commands still get cut — this must not fix the curve by
    /// giving up on animating the factor.
    @Test("an animated factor still produces its own commands")
    func factorStillAnimates() throws {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: 2000)
        let added = document.addFilter(GlowFilter.descriptor, to: node.id)
        let filter = try #require(added)
        document.setFilterAnimation(
            KeyframeTrack([
                Keyframe(time: 0, value: 0.2),
                Keyframe(time: 1000, value: 1.5),
            ]),
            for: GlowFilter.Param.intensity, on: filter.id, in: node.id,
        )

        let halos = evaluator.evaluate(document).filter { $0.id.contains("/g") }
        let halo = try #require(halos.first)
        let fades = halo.commands.filter { $0.kind == .fade }
        #expect(fades.count > 1, "the animated factor must be cut into segments")
    }
}

/// Which family each transform property belongs to.
///
/// Nine rows of identical diamonds is a wall; a colour per family lets the eye
/// find "the position keys" without reading a label. The grouping matters more
/// than the colours: X and Y are two halves of one move, and colouring them
/// apart would say they are unrelated.
@Suite("Keyframe families")
struct KeyframeFamilyTests {
    @Test("the two halves of a pair share a family")
    func pairsShareAFamily() {
        #expect(TransformProperty.x.family == TransformProperty.y.family)
        #expect(TransformProperty.scaleX.family == TransformProperty.scaleY.family)
        // Colour is three channels of one command, so all three go together.
        #expect(TransformProperty.red.family == TransformProperty.green.family)
        #expect(TransformProperty.green.family == TransformProperty.blue.family)
    }

    /// Different families must actually differ, or the colouring says nothing.
    @Test("unrelated properties are in different families")
    func unrelatedDiffer() {
        let families: [TransformProperty.Family] = [
            .position, .scale, .rotation, .opacity, .colour,
        ]
        #expect(Set(families).count == families.count)
        #expect(TransformProperty.x.family != TransformProperty.scaleX.family)
        #expect(TransformProperty.rotation.family != TransformProperty.opacity.family)
    }

    /// Every property has one, so no row falls back to a default that means
    /// "unclassified" while sitting beside eight that are classified.
    @Test("every property has a family")
    func everyPropertyIsClassified() {
        let byFamily = Dictionary(grouping: TransformProperty.allCases, by: \.family)
        #expect(byFamily.keys.count == 5)
        #expect(byFamily.values.map(\.count).reduce(0, +) == TransformProperty.allCases.count)
    }
}
