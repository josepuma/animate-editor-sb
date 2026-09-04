import Testing

@testable import StoryboardCore

@Suite("EffectParameter")
struct EffectParameterTests {
    private let bounded = EffectParameter(
        id: "opacity",
        name: "Opacity",
        group: "Appearance",
        defaultValue: .number(1),
        range: 0...1,
    )

    private let choice = EffectParameter(
        id: "emission",
        name: "Emission",
        group: "Emission",
        defaultValue: .choice("Continuous"),
        options: ["Burst", "Continuous"],
    )

    @Test("a value inside the range passes through")
    func inRange() {
        #expect(bounded.coerce(.number(0.5)) == .number(0.5))
    }

    @Test("a value outside the range is clamped, not rejected")
    func clamped() {
        #expect(bounded.coerce(.number(4)) == .number(1))
        #expect(bounded.coerce(.number(-2)) == .number(0))
    }

    @Test("a value of the wrong kind falls back to the default")
    func wrongKind() {
        #expect(bounded.coerce(.toggle(true)) == .number(1))
    }

    @Test("an integer is clamped and rounded")
    func integerClamping() {
        let count = EffectParameter(
            id: "count",
            name: "Particles",
            group: "Emission",
            defaultValue: .integer(10),
            range: 1...100,
        )

        #expect(count.coerce(.integer(500)) == .integer(100))
        #expect(count.coerce(.number(12.6)) == .integer(10))  // wrong kind → default
    }

    /// A preset renamed between sessions would otherwise leave the inspector
    /// displaying a selection its own menu does not contain.
    @Test("a choice that is no longer an option falls back to the default")
    func staleChoice() {
        #expect(choice.coerce(.choice("Burst")) == .choice("Burst"))
        #expect(choice.coerce(.choice("Spiral")) == .choice("Continuous"))
    }

    @Test("groups come out in declaration order, without repeats")
    func groupOrder() {
        #expect(EmitterEffect.descriptor.groups == [
            "Emission", "Shape", "Position", "Direction", "Physics",
            "Particle", "Appearance",
        ])
    }

    @Test("every declared parameter has a matching default")
    func defaultsCoverEveryParameter() {
        let descriptor = EmitterEffect.descriptor
        #expect(descriptor.defaultValues.count == descriptor.parameters.count)
    }

    /// A parameter read with an id that does not exist silently yields zero, so
    /// the constants and the declaration have to agree.
    @Test("every id the emitter reads is a declared parameter")
    func readIdsAreDeclared() {
        let declared = Set(EmitterEffect.descriptor.parameters.map(\.id))
        let read = [
            EmitterEffect.Param.count, EmitterEffect.Param.emission,
            EmitterEffect.Param.burstCount, EmitterEffect.Param.sprite,
            EmitterEffect.Param.width, EmitterEffect.Param.height,
            EmitterEffect.Param.shape, EmitterEffect.Param.radial,
            EmitterEffect.Param.tilt, EmitterEffect.Param.bands,
            EmitterEffect.Param.swirl,
            EmitterEffect.Param.direction, EmitterEffect.Param.spread,
            EmitterEffect.Param.velocity, EmitterEffect.Param.velocityRandom,
            EmitterEffect.Param.gravity, EmitterEffect.Param.drag,
            EmitterEffect.Param.life, EmitterEffect.Param.lifeRandom,
            EmitterEffect.Param.scaleStart, EmitterEffect.Param.scaleEnd,
            EmitterEffect.Param.scaleRandom, EmitterEffect.Param.stretch,
            EmitterEffect.Param.rotation, EmitterEffect.Param.alignToMotion,
            EmitterEffect.Param.spin,
            EmitterEffect.Param.color, EmitterEffect.Param.colorEnd,
            EmitterEffect.Param.colorMid, EmitterEffect.Param.usesColorMid,
            EmitterEffect.Param.colorVariety,
            EmitterEffect.Param.opacity,
            EmitterEffect.Param.fadeIn, EmitterEffect.Param.fadeOut,
            EmitterEffect.Param.additive,
            // The particle's own form, built from numbers rather than picked
            // from a list of nine textures.
            EmitterEffect.Param.core, EmitterEffect.Param.edge,
            EmitterEffect.Param.softness,
        ]

        #expect(Set(read) == declared)
    }

    // ─── Context ─────────────────────────────────────────────────────────────

    @Test("a node missing a value reads the declared default")
    func missingValueFallsBack() {
        let node = EffectNode(id: "n", type: "emitter", name: "E", startTime: 0, duration: 1000)
        let context = EffectContext(descriptor: EmitterEffect.descriptor, node: node)

        #expect(context.integer(EmitterEffect.Param.count) == 120)
        #expect(context.number(EmitterEffect.Param.life) == 1200)
    }

    @Test("a stored value out of range is clamped when read")
    func storedValueIsCoerced() {
        let node = EffectNode(
            id: "n", type: "emitter", name: "E", startTime: 0, duration: 1000,
            values: [EmitterEffect.Param.count: .integer(99_999)],
        )
        let context = EffectContext(descriptor: EmitterEffect.descriptor, node: node)

        #expect(context.integer(EmitterEffect.Param.count) == EmitterEffect.maximumCount)
    }
}

@Suite("EffectRandom")
struct EffectRandomTests {
    @Test("the same seed replays the same stream")
    func reproducible() {
        var a = EffectRandom(seed: 7)
        var b = EffectRandom(seed: 7)

        #expect((0..<20).map { _ in a.unit() } == (0..<20).map { _ in b.unit() })
    }

    @Test("values stay in [0, 1)")
    func unitRange() {
        var rng = EffectRandom(seed: 3)
        for _ in 0..<500 {
            let value = rng.unit()
            #expect(value >= 0 && value < 1)
        }
    }

    /// Per-item streams are what let the particle count grow without
    /// reshuffling the particles already placed.
    /// The bug this pins: deriving a stream by adding the index left seeds 1
    /// and 2 producing near-identical fields, because SplitMix64's own
    /// increment swamps a difference of one before the mix. Nudging a seed
    /// field looked like it did nothing.
    @Test("adjacent seeds produce uncorrelated streams")
    func adjacentSeedsDiverge() {
        var first = EffectRandom(seed: 1).stream(0)
        var second = EffectRandom(seed: 2).stream(0)

        let a = (0..<8).map { _ in first.unit() }
        let b = (0..<8).map { _ in second.unit() }

        // Uncorrelated draws land far apart; correlated ones agree to several
        // decimal places, which is exactly how the bug presented.
        #expect(zip(a, b).allSatisfy { abs($0 - $1) > 1e-6 })
    }

    @Test("a derived stream depends only on its index")
    func streamsAreStable() {
        let base = EffectRandom(seed: 11)
        var first = base.stream(4)
        var second = base.stream(4)
        var other = base.stream(5)

        #expect(first.unit() == second.unit())
        #expect(base.stream(4).valueForTesting != other.unit())
    }
}

private extension EffectRandom {
    var valueForTesting: Double {
        var copy = self
        return copy.unit()
    }
}
