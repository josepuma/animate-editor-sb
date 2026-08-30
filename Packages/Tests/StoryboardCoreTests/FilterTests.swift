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
    private func document(count: Int = 10) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(count), for: EmitterEffect.Param.count, on: node.id)
        return document
    }

    // ─── Glow ────────────────────────────────────────────────────────────────

    /// One halo per sprite, whatever the softness. The point of blurring is
    /// that a softer glow costs pixels rather than sprites: the old design
    /// stacked a copy per layer, so three layers over two hundred particles was
    /// six hundred sprites.
    @Test("a glow adds exactly one halo per sprite")
    func glowAddsOneHalo() {
        var document = document(count: 10)
        let trackID = document.tracks[0].id
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        #expect(evaluator.evaluate(document).count == 20)
    }

    /// Softness must not change the sprite count — that is the whole gain.
    @Test("softness costs no extra sprites")
    func softnessIsFree() {
        var document = document(count: 10)
        let trackID = document.tracks[0].id
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
        let trackID = document.tracks[0].id
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
        let trackID = document.tracks[0].id
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
        let trackID = document.tracks[0].id
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
        let trackID = document.tracks[0].id
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
        let trackID = document.tracks[0].id
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        let sprites = evaluator.evaluate(document)
        let lastHalo = sprites.lastIndex { $0.id.contains("/g") }!
        let firstOriginal = sprites.firstIndex { !$0.id.contains("/g") }!

        #expect(lastHalo < firstOriginal)
    }

    @Test("a disabled filter changes nothing")
    func disabledFilterIsSkipped() {
        var document = document(count: 5)
        let trackID = document.tracks[0].id
        let plain = evaluator.evaluate(document).count

        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!
        #expect(evaluator.evaluate(document).count > plain)

        document.toggleFilter(filter.id, in: trackID)
        #expect(evaluator.evaluate(document).count == plain)
    }

    @Test("a glow with no intensity leaves the sprites alone")
    func zeroIntensityIsANoOp() {
        var document = document(count: 5)
        let trackID = document.tracks[0].id
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0), for: GlowFilter.Param.intensity, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).count == 5)
    }

    // ─── Echo ────────────────────────────────────────────────────────────────

    @Test("an echo adds a copy per repeat, offset backwards in time")
    func echoTrails() {
        var document = document(count: 4)
        let trackID = document.tracks[0].id
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
        let trackID = document.tracks[0].id

        _ = document.addFilter(GlowFilter.descriptor, to: trackID)
        let echo = document.addFilter(EchoFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(1), for: EchoFilter.Param.count, on: echo.id, in: trackID)

        // 2 sprites → glow ×2 → 4 → echo ×2 → 8.
        #expect(evaluator.evaluate(document).count == 8)
        #expect(evaluator.spriteMultiplier(for: document.tracks[0]) == 4)
    }

    /// The number that matters before an export: a glow over a large emitter is
    /// a file osu! will not open.
    @Test("the multiplier counts only enabled filters")
    func multiplierRespectsEnabling() {
        var document = document(count: 1)
        let trackID = document.tracks[0].id
        let filter = document.addFilter(GlowFilter.descriptor, to: trackID)!

        #expect(evaluator.spriteMultiplier(for: document.tracks[0]) == 2)

        document.toggleFilter(filter.id, in: trackID)
        #expect(evaluator.spriteMultiplier(for: document.tracks[0]) == 1)
    }

    @Test("a hidden track runs no filters")
    func hiddenTrackSkipsFilters() {
        var document = document(count: 5)
        let trackID = document.tracks[0].id
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        document.toggleVisibility(of: trackID)
        #expect(evaluator.evaluate(document).isEmpty)
    }

    @Test("filtered sprites take the track's layer")
    func filteredSpritesTakeTheLayer() {
        var document = EffectDocument()
        let track = document.addTrack(named: "Behind", layer: .background)
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 1000, on: track.id)
        document.setValue(.integer(3), for: EmitterEffect.Param.count, on: node.id)
        _ = document.addFilter(GlowFilter.descriptor, to: track.id)

        #expect(evaluator.evaluate(document).allSatisfy { $0.layer == .background })
    }

    /// Two filters on one lane must not produce colliding sprite ids.
    @Test("filter output ids are unique")
    func idsDoNotCollide() {
        var document = document(count: 6)
        let trackID = document.tracks[0].id
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
            case .toggle, .color, .text:
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

    @Test("a blur adds no sprites at all")
    func blurIsFree() {
        var document = document(count: 8)
        let trackID = document.tracks[0].id
        _ = document.addFilter(BlurFilter.descriptor, to: trackID)

        #expect(evaluator.evaluate(document).count == 8)
        #expect(evaluator.spriteMultiplier(for: document.tracks[0]) == 1)
    }

    @Test("every sprite draws a softened copy of its own image")
    func spritesAreDerived() {
        var document = document(count: 4)
        let trackID = document.tracks[0].id
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(10), for: BlurFilter.Param.radius, on: filter.id, in: trackID)

        let plainPaths = Set(EffectEvaluator().evaluate(document.tracks[0].nodes).map(\.filePath))
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
        let trackID = document.tracks[0].id
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0), for: BlurFilter.Param.radius, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).allSatisfy { !DerivedSprite.isDerived($0.filePath) })
    }

    /// Blurring spreads a sprite's light over a larger area, so the same
    /// opacity reads brighter than the original did.
    @Test("opacity scales the sprites' own fades")
    func opacityScalesFades() {
        var document = document(count: 2)
        let trackID = document.tracks[0].id
        let filter = document.addFilter(BlurFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.5), for: BlurFilter.Param.opacity, on: filter.id, in: trackID)

        let plain = EffectEvaluator().evaluate(document.tracks[0].nodes)
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
        let trackID = document.tracks[0].id
        _ = document.addFilter(BlurFilter.descriptor, to: trackID)
        _ = document.addFilter(GlowFilter.descriptor, to: trackID)

        // Blur adds nothing, glow doubles.
        #expect(evaluator.evaluate(document).count == 6)
        #expect(evaluator.spriteMultiplier(for: document.tracks[0]) == 2)
    }
}
