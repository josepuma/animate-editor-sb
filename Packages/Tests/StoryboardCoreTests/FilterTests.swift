import Foundation
import Testing

@testable import StoryboardCore

/// Filters transform what a track produced rather than producing anything, and
/// they run during evaluation — not at export. That is the property everything
/// else rests on: what the canvas draws is what the file will contain.
@Suite("Sprite filters")
struct FilterTests {
    private let evaluator = EffectEvaluator()

    /// One emitter on one track, with `count` particles.
    /// One emitter on one track, with `count` particles.
    private func document(count: Int = 10) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(count), for: EmitterEffect.Param.count, on: node.id)
        return document
    }

    /// The clip filters are applied to.
    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    // ─── Glow ────────────────────────────────────────────────────────────────

    /// One halo per sprite, whatever the softness. The point of blurring is
    /// that a softer glow costs pixels rather than sprites: the old design
    /// stacked a copy per layer, so three layers over two hundred particles was
    /// six hundred sprites.
    @Test("a glow adds exactly one halo per sprite")
    func glowAddsOneHalo() {
        var document = document(count: 10)
        let trackID = clip(in: document)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        #expect(evaluator.evaluate(document).count == 20)
    }

    /// Softness must not change the sprite count — that is the whole gain.
    @Test("softness costs no extra sprites")
    func softnessIsFree() {
        var document = document(count: 10)
        let trackID = clip(in: document)
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!

        for radius in [0.0, 8.0, 40.0] {
            document.setFilterValue(
                .number(radius), for: GlowFilter.Param.radius, on: filter.id, in: trackID,
            )
            #expect(evaluator.evaluate(document).count == 20)
        }
    }

    @Test("the halo draws a blurred copy of its sprite")
    func haloUsesADerivedSprite() {
        var document = document(count: 3)
        let trackID = clip(in: document)
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(16), for: GlowFilter.Param.radius, on: filter.id, in: trackID)

        let sprites = evaluator.evaluate(document)
        let halos = sprites.filter { $0.id.contains("/g") }
        let originals = sprites.filter { !$0.id.contains("/g") }

        #expect(halos.allSatisfy { DerivedSprite.isDerived($0.filePath) })
        // And the derivation names the sprite it came from, so the loader can
        // find the original to blur.
        for (halo, original) in zip(halos, originals) {
            #expect(DerivedSprite.parse(halo.filePath)?.source == original.filePath)
        }
    }

    /// Zero softness is a plain enlarged additive copy, for anyone who wants
    /// hard edges — and it should not mint a texture to say so.
    @Test("no softness leaves the path alone")
    func zeroRadiusKeepsThePath() {
        var document = document(count: 2)
        let trackID = clip(in: document)
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0), for: GlowFilter.Param.radius, on: filter.id, in: trackID)

        let sprites = evaluator.evaluate(document)
        #expect(sprites.allSatisfy { !DerivedSprite.isDerived($0.filePath) })
    }

    /// Light adds; it does not occlude. Without additive the halo is a grey
    /// wash behind the sprite rather than a glow around it.
    @Test("halo copies are additive")
    func haloIsAdditive() {
        var document = document(count: 4)
        let trackID = clip(in: document)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        let sprites = evaluator.evaluate(document)
        let halos = sprites.filter { $0.id.contains("/g") }

        #expect(!halos.isEmpty)
        #expect(halos.allSatisfy { sprite in
            sprite.commands.contains { command in
                if case .parameter(.additive) = command.payload { return true }
                return false
            }
        })
    }

    @Test("the halo is larger than its sprite")
    func haloIsLargerAndFainter() {
        var document = document(count: 1)
        let trackID = clip(in: document)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        let sprites = evaluator.evaluate(document)
        let prepared = StoryboardResolver.prepare(sprites)

        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: 1000, into: &states)
        let visible = states.filter { $0.visible && $0.opacity > 0.001 }

        let halos = visible.filter { $0.spriteId.contains("/g") }
        let originals = visible.filter { !$0.spriteId.contains("/g") }

        #expect(!halos.isEmpty)
        #expect(!originals.isEmpty)
        #expect(halos.map(\.scaleX).max()! > originals.map(\.scaleX).max()!)
    }

    /// Drawn after its subject, a halo washes over it and the result reads as
    /// fog rather than as light.
    @Test("halos are drawn behind their sprites")
    func halosComeFirst() {
        var document = document(count: 3)
        let trackID = clip(in: document)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        let sprites = evaluator.evaluate(document)
        let lastHalo = sprites.lastIndex { $0.id.contains("/g") }!
        let firstOriginal = sprites.firstIndex { !$0.id.contains("/g") }!

        #expect(lastHalo < firstOriginal)
    }

    @Test("a disabled filter changes nothing")
    func disabledFilterIsSkipped() {
        var document = document(count: 5)
        let trackID = clip(in: document)
        let plain = evaluator.evaluate(document).count

        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!
        #expect(evaluator.evaluate(document).count > plain)

        document.toggleFilter(filter.id, in: trackID)
        #expect(evaluator.evaluate(document).count == plain)
    }

    @Test("a glow with no intensity leaves the sprites alone")
    func zeroIntensityIsANoOp() {
        var document = document(count: 5)
        let trackID = clip(in: document)
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0), for: GlowFilter.Param.intensity, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).count == 5)
    }

    // ─── Echo ────────────────────────────────────────────────────────────────

    /// The trail parameters are inert at their defaults.
    ///
    /// `Shrink` and `Trail Colour` turn the echo into a streak, and they were
    /// added to a filter people already have in saved projects. A default that
    /// changed the output would rewrite work that was already finished and
    /// approved — so the plain echo has to come out identical, sprite for
    /// sprite and command for command.
    @Test("adding the trail parameters leaves a plain echo untouched")
    func trailDefaultsAreInert() {
        var document = document(count: 6)
        let trackID = clip(in: document)
        let filter = document.addFilter(EchoFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(3), for: EchoFilter.Param.count, on: filter.id, in: trackID)

        let withDefaults = evaluator.evaluate(document)

        // Spelled out rather than left implicit: this is the comparison, so the
        // values it rests on cannot be assumed.
        document.setFilterValue(.number(0), for: EchoFilter.Param.shrink, on: filter.id, in: trackID)
        document.setFilterValue(
            .color(EffectColor(r: 255, g: 255, b: 255)),
            for: EchoFilter.Param.tint, on: filter.id, in: trackID,
        )
        let explicit = evaluator.evaluate(document)

        #expect(withDefaults.count == explicit.count)
        for (a, b) in zip(withDefaults, explicit) {
            #expect(a.id == b.id)
            #expect(a.filePath == b.filePath)
            #expect(a.commands.count == b.commands.count)
            for (one, two) in zip(a.commands, b.commands) {
                #expect(one.kind == two.kind)
                #expect(one.startTime == two.startTime)
                #expect(one.endTime == two.endTime)
            }
        }
    }

    /// Turned up, the copies shrink — which is the difference between an echo
    /// and a trail.
    @Test("shrink makes the older copies smaller")
    func shrinkRecedes() {
        var document = document(count: 4)
        let trackID = clip(in: document)
        let filter = document.addFilter(EchoFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(4), for: EchoFilter.Param.count, on: filter.id, in: trackID)
        document.setFilterValue(.number(0.8), for: EchoFilter.Param.shrink, on: filter.id, in: trackID)

        let sprites = evaluator.evaluate(document)

        func scale(_ sprite: StoryboardSprite) -> Double? {
            for command in sprite.commands {
                if case let .scale(start, _) = command.payload { return start }
            }
            return nil
        }

        // The furthest copy carries the smallest scale, and the subject itself
        // is untouched: a trail recedes behind what it follows.
        let echoes = sprites.filter { $0.id.contains("/e") }
        let scales = echoes.compactMap(scale)

        #expect(!scales.isEmpty, "no echo carried a scale")
        #expect(scales.min()! < scales.max()!, "every copy came out the same size")
    }



    @Test("an echo adds a copy per repeat, offset backwards in time")
    func echoTrails() {
        var document = document(count: 4)
        let trackID = clip(in: document)
        let filter = document.addFilter(EchoFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(3), for: EchoFilter.Param.count, on: filter.id, in: trackID)
        document.setFilterValue(.number(100), for: EchoFilter.Param.delay, on: filter.id, in: trackID)

        let sprites = evaluator.evaluate(document)
        #expect(sprites.count == 16)

        let echoes = sprites.filter { $0.id.contains("/e") }
        let originals = sprites.filter { !$0.id.contains("/e") }

        // An echo shows where its subject *was*, so it starts earlier.
        let earliestEcho = echoes.flatMap { $0.commands.map(\.startTime) }.min()!
        let earliestOriginal = originals.flatMap { $0.commands.map(\.startTime) }.min()!
        #expect(earliestEcho < earliestOriginal)
    }

    // ─── Composition ─────────────────────────────────────────────────────────

    /// Filters compose in order: a glow after an echo lights the trail, and
    /// before it the trail carries copies of the glow.
    @Test("filters apply in the order they were added")
    func filtersCompose() {
        var document = document(count: 2)
        let trackID = clip(in: document)

        _ = document.addFilter(GlowFilter.descriptor, to: trackID)
        let echo = document.addFilter(EchoFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(1), for: EchoFilter.Param.count, on: echo.id, in: trackID)

        // 2 sprites → glow ×2 → 4 → echo ×2 → 8.
        #expect(evaluator.evaluate(document).count == 8)
        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 4)
    }

    /// The number that matters before an export: a glow over a large emitter is
    /// a file osu! will not open.
    @Test("the multiplier counts only enabled filters")
    func multiplierRespectsEnabling() {
        var document = document(count: 1)
        let trackID = clip(in: document)
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!

        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 2)

        document.toggleFilter(filter.id, in: trackID)
        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 1)
    }

    @Test("a hidden track runs no filters")
    func hiddenTrackSkipsFilters() {
        var document = document(count: 5)
        let trackID = clip(in: document)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        document.toggleVisibility(of: document.tracks[0].id)
        #expect(evaluator.evaluate(document).isEmpty)
    }

    @Test("filtered sprites take the track's layer")
    func filteredSpritesTakeTheLayer() {
        var document = EffectDocument()
        let track = document.addTrack(named: "Behind", layer: .background)
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 1000, on: track.id)
        document.setValue(.integer(3), for: EmitterEffect.Param.count, on: node.id)
        _ = document.addFilter(GlowFilter.descriptor, to: node.id)

        #expect(evaluator.evaluate(document).allSatisfy { $0.layer == .background })
    }

    /// Two filters on one lane must not produce colliding sprite ids.
    @Test("filter output ids are unique")
    func idsDoNotCollide() {
        var document = document(count: 6)
        let trackID = clip(in: document)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)
        _ = document.addFilter(EchoFilter.descriptor, to: trackID)

        let sprites = evaluator.evaluate(document)
        #expect(Set(sprites.map(\.id)).count == sprites.count)
    }

    // ─── Declarations ────────────────────────────────────────────────────────

    @Test("every filter declares renderable parameters", arguments: FilterLibrary.standard.descriptors)
    func declarationsAreRenderable(descriptor: FilterDescriptor) {
        #expect(!descriptor.name.isEmpty)
        #expect(!descriptor.parameters.isEmpty)

        for parameter in descriptor.parameters {
            switch parameter.kind {
            case .number, .integer:
                #expect(parameter.range != nil, "\(parameter.id) has no range")
                #expect(parameter.presentation != .slider || parameter.range != nil)
            case .choice:
                #expect(!parameter.options.isEmpty)
            // A path is drawn on the canvas, so it declares no bounds and
            // no options — there is nothing for the inspector to render.
            case .toggle, .color, .text, .path:
                break
            }
        }
    }
}

/// Blur is the one filter that adds nothing: it swaps each sprite's image for a
/// softened copy of itself. Softness lives in the pixels, so the file does not
/// grow at all.
@Suite("Blur filter")
struct BlurFilterTests {
    private let evaluator = EffectEvaluator()

    private func document(count: Int = 8) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(count), for: EmitterEffect.Param.count, on: node.id)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    @Test("a blur adds no sprites at all")
    func blurIsFree() {
        var document = document(count: 8)
        let trackID = clip(in: document)
        _ = document.addFilter(BlurFilter.descriptor, to: trackID)

        #expect(evaluator.evaluate(document).count == 8)
        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 1)
    }

    @Test("every sprite draws a softened copy of its own image")
    func spritesAreDerived() {
        var document = document(count: 4)
        let trackID = clip(in: document)
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(10), for: BlurFilter.Param.radius, on: filter.id, in: trackID)

        // A copy with no filters: `evaluate` applies a clip's own filters now,
        // so the unfiltered document is the only honest baseline.
        var bareNodes = document.nodes
        for index in bareNodes.indices { bareNodes[index].filters = [] }
        let plainPaths = Set(EffectEvaluator().evaluate(bareNodes).map(\.filePath))
        let sprites = evaluator.evaluate(document)

        #expect(sprites.allSatisfy { DerivedSprite.isDerived($0.filePath) })
        // And each one names the image it came from.
        #expect(sprites.allSatisfy { sprite in
            DerivedSprite.parse(sprite.filePath).map { plainPaths.contains($0.source) } ?? false
        })
    }

    @Test("a radius of zero leaves the sprites untouched")
    func zeroRadiusIsANoOp() {
        var document = document(count: 4)
        let trackID = clip(in: document)
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0), for: BlurFilter.Param.radius, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).allSatisfy { !DerivedSprite.isDerived($0.filePath) })
    }

    /// Blurring spreads a sprite's light over a larger area, so the same
    /// opacity reads brighter than the original did.
    @Test("opacity scales the sprites' own fades")
    func opacityScalesFades() {
        var document = document(count: 2)
        let trackID = clip(in: document)
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.5), for: BlurFilter.Param.opacity, on: filter.id, in: trackID)

        var bareNodes = document.nodes
        for index in bareNodes.indices { bareNodes[index].filters = [] }
        let plain = EffectEvaluator().evaluate(bareNodes)
        let blurred = evaluator.evaluate(document)

        for (before, after) in zip(plain, blurred) {
            for (a, b) in zip(before.commands, after.commands) {
                guard case let .fade(_, endBefore) = a.payload,
                      case let .fade(_, endAfter) = b.payload
                else { continue }
                #expect(abs(endAfter - endBefore * 0.5) < 1e-9)
            }
        }
    }

    /// Composed with a glow, the halo softens twice — the blur first, then the
    /// glow's own derivation of the already-soft image.
    @Test("blur and glow compose")
    func composesWithGlow() {
        var document = document(count: 3)
        let trackID = clip(in: document)
        _ = document.addFilter(BlurFilter.descriptor, to: trackID)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        // Blur adds nothing, glow doubles.
        #expect(evaluator.evaluate(document).count == 6)
        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 2)
    }
}

/// The one filter that makes a storyboard *smaller*.
///
/// osu! has a real loop construct — a body written once and an iteration count
/// — so a two-second effect repeated ten times is one copy of the commands and
/// a number, not ten copies.
@Suite("Loop filter")
struct LoopFilterTests {

    /// A loop body is replayed from zero every pass, so a sprite with no
    /// command over its opening stretch is drawn at whatever its default
    /// opacity is — visible. Every particle not yet born appeared at once at
    /// the top of each iteration, held, and the sequence began underneath them.
    ///
    /// Invisible in the editor and plain in the game: this resolver treats an
    /// uncommanded sprite as not drawn, and osu! draws it.
    @Test("a looped body is covered from its first moment")
    func loopBodyCoversItsStart() {
        var late = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "a.png", defaultX: 320, defaultY: 240,
        )
        late.commands = [Command(
            easing: .linear, startTime: 800, endTime: 1400,
            payload: .fade(start: 0, end: 1),
        )]

        let context = FilterContext(
            descriptor: LoopFilter.descriptor,
            node: FilterNode(id: "l", type: LoopFilter.descriptor.type, values: [:]),
        )
        let body = LoopFilter().apply(to: [late], in: context)[0].loops[0].commands

        // Nothing between zero and the first command.
        #expect(body.map(\.startTime).min() == 0)

        // And the sprite is invisible there.
        let opening = body.first { $0.startTime == 0 }
        if case let .fade(start, end) = opening?.payload {
            #expect(start == 0 && end == 0)
        } else {
            Issue.record("the body's opening command should be a fade to nothing")
        }
    }

    private let evaluator = EffectEvaluator()

    private func document(count: Int = 6) -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(count), for: EmitterEffect.Param.count, on: node.id)
        return (document, node.id)
    }

    /// The whole point: repeating costs a number, not copies.
    @Test("looping adds no sprites")
    func loopingIsCheap() {
        var (document, trackID) = document(count: 6)
        let plain = evaluator.evaluate(document).count

        let filter = document.addFilter(LoopFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(10), for: LoopFilter.Param.count, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).count == plain)
        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 1)
    }

    @Test("commands move into a loop body")
    func commandsBecomeALoopBody() {
        var (document, trackID) = document(count: 3)
        let before = evaluator.evaluate(document)
        _ = document.addFilter(LoopFilter.descriptor, to: trackID)
        let after = evaluator.evaluate(document)

        #expect(before.allSatisfy { $0.loops.isEmpty })
        #expect(after.allSatisfy { $0.loops.count == 1 })
        // Nothing is left outside the loop: a command there would play once
        // while its own sprite repeated around it.
        #expect(after.allSatisfy { $0.commands.isEmpty })
    }

    @Test("the clip repeats for as long as its count says")
    func repeatsForTheWholeSpan() {
        var (document, trackID) = document(count: 4)
        let filter = document.addFilter(LoopFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(5), for: LoopFilter.Param.count, on: filter.id, in: trackID)

        let prepared = StoryboardResolver.prepare(evaluator.evaluate(document))

        // Five passes over a two-second clip reach past eight seconds.
        #expect(prepared.first.map { $0.activeEnd > 8000 } == true)
    }

    /// A loop's period comes from the longest command in its own body, so left
    /// alone each sprite would repeat on its own schedule — a field of
    /// particles drifting apart into noise after the first pass.
    @Test("every sprite repeats on the same period")
    func iterationsShareAPeriod() {
        var (document, trackID) = document(count: 8)
        _ = document.addFilter(LoopFilter.descriptor, to: trackID)

        let periods = evaluator.evaluate(document).compactMap { sprite in
            sprite.loops.first?.commands.map(\.endTime).max()
        }

        #expect(periods.count == 8)
        #expect(Set(periods.map { ($0 * 100).rounded() }).count == 1)
    }

    /// A gap makes it a beat that repeats rather than a stream that never
    /// stops.
    @Test("a gap lengthens the period")
    func gapExtendsThePeriod() {
        func period(gap: Double) -> Double {
            var (document, trackID) = document(count: 2)
            let filter = document.addFilter(LoopFilter.descriptor, to: trackID)!
            document.setFilterValue(.number(gap), for: LoopFilter.Param.gap, on: filter.id, in: trackID)
            return evaluator.evaluate(document)
                .first?.loops.first?.commands.map(\.endTime).max() ?? 0
        }

        #expect(period(gap: 1000) > period(gap: 0) + 900)
    }

    /// One repeat is not a loop, and the parameter says so: its range starts at
    /// two, so a value of one is clamped before it ever reaches the filter.
    @Test("a single repeat cannot be asked for")
    func singleRepeatIsClamped() {
        let parameter = LoopFilter.descriptor.parameter(LoopFilter.Param.count)

        #expect(parameter?.range?.lowerBound == 2)
        #expect(parameter?.coerce(.integer(1)) == .integer(2))
    }

    /// The bug this pins: reported as a multiple, the ghost drawn on the
    /// timeline stayed the same length whatever the gap — a factor cannot say
    /// "this many passes *plus* a fixed silence".
    @Test("a gap lengthens how long the clip runs")
    func gapExtendsTheDuration() {
        func played(gap: Double) -> Double {
            var (document, trackID) = document(count: 2)
            let filter = document.addFilter(LoopFilter.descriptor, to: trackID)!
            document.setFilterValue(.integer(4), for: LoopFilter.Param.count, on: filter.id, in: trackID)
            document.setFilterValue(.number(gap), for: LoopFilter.Param.gap, on: filter.id, in: trackID)
            return evaluator.duration(of: 2000, on: document.nodes[0])
        }

        // Four passes of two seconds is eight; a second of silence each makes
        // it twelve.
        #expect(played(gap: 0) == 8000)
        #expect(played(gap: 1000) == 12_000)
    }

    @Test("a filter that changes nothing leaves the duration alone")
    func otherFiltersDoNotStretch() {
        var (document, trackID) = document(count: 2)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        #expect(evaluator.duration(of: 2000, on: document.nodes[0]) == 2000)
    }

    /// The bug this pins: filters ran *before* the clip's transform, so a loop
    /// packed the commands into a loop body and the transform then wrote its
    /// movement outside that body. The animation played once and the sprite sat
    /// frozen at its last value for every remaining pass — which is exactly
    /// what it looked like.
    @Test("a looped clip repeats its animation, not just its first pass")
    func loopRepeatsTheAnimation() {
        var document = EffectDocument()
        var node = document.add(ImageEffect.descriptor, at: 0, duration: 1000)
        node.values[ImageEffect.Param.sprite] = .text("a.png")
        node.transform[.x] = KeyframeTrack([
            Keyframe(time: 0, value: 100),
            Keyframe(time: 1000, value: 500),
        ])
        document[node.id] = node

        let filter = document.addFilter(LoopFilter.descriptor, to: node.id)!
        document.setFilterValue(.integer(3), for: LoopFilter.Param.count, on: filter.id, in: node.id)

        let sprite = evaluator.evaluate(document)[0]

        // Everything is inside the loop: a command left outside plays once
        // while its own sprite repeats around it.
        #expect(sprite.commands.isEmpty)
        #expect(sprite.loops.first?.commands.contains { $0.kind == .move } == true)

        // And the movement actually replays.
        let prepared = StoryboardResolver.prepare([sprite])
        func x(at time: Double) -> Double {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: time, into: &states)
            return states.first?.x ?? -1
        }

        #expect(x(at: 0) == x(at: 1000))
        #expect(x(at: 500) == x(at: 1500))
        #expect(x(at: 500) != x(at: 1000))
    }

    /// Composed after a glow, the halo loops with what it surrounds.
    @Test("looping composes with other filters")
    func composesWithGlow() {
        var (document, trackID) = document(count: 3)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)
        _ = document.addFilter(LoopFilter.descriptor, to: trackID)

        let sprites = evaluator.evaluate(document)

        // Glow doubled the sprites; the loop left the count alone and put
        // every one of them into a loop body.
        #expect(sprites.count == 6)
        #expect(sprites.allSatisfy { $0.loops.count == 1 })
    }
}
