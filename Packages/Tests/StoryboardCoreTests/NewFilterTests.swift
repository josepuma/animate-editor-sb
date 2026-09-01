import Testing

@testable import StoryboardCore

@Suite("Stylise filters")
struct NewFilterTests {
    private func subject(moving: Bool = false) -> [StoryboardSprite] {
        var sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "a.png", defaultX: 320, defaultY: 240,
        )
        sprite.commands = [Command(
            easing: .linear, startTime: 0, endTime: 2000, payload: .fade(start: 1, end: 1),
        )]
        if moving {
            sprite.commands.append(Command(
                easing: .linear, startTime: 0, endTime: 2000,
                payload: .move(startX: 100, startY: 100, endX: 400, endY: 400),
            ))
        }
        return [sprite]
    }

    private func context(_ descriptor: FilterDescriptor, _ values: [String: EffectValue] = [:])
        -> FilterContext
    {
        FilterContext(
            descriptor: descriptor,
            node: FilterNode(id: "f1", type: descriptor.type, values: values),
        )
    }

    // ─── Tint ────────────────────────────────────────────────────────────────

    /// One command per sprite, no copies — the cheapest thing in the library.
    @Test("a tint adds no sprites")
    func tintCostsNothing() {
        let out = TintFilter().apply(to: subject(), in: context(TintFilter.descriptor))
        #expect(out.count == 1)
        #expect(out[0].commands.contains { $0.kind == .color })
    }

    /// Replaced rather than layered: two tints multiplying would darken with
    /// every one, and "tint this blue" is a statement about the result.
    @Test("a tint replaces an existing colour")
    func tintReplaces() {
        var sprites = subject()
        sprites[0].commands.append(Command(
            easing: .linear, startTime: 0, endTime: 0,
            payload: .color(startR: 255, startG: 0, startB: 0, endR: 255, endG: 0, endB: 0),
        ))

        let out = TintFilter().apply(to: sprites, in: context(TintFilter.descriptor))
        #expect(out[0].commands.filter { $0.kind == .color }.count == 1)
    }

    // ─── Shadow ──────────────────────────────────────────────────────────────

    @Test("a shadow doubles the sprites")
    func shadowDoubles() {
        let out = ShadowFilter().apply(to: subject(), in: context(ShadowFilter.descriptor))
        #expect(out.count == 2)
    }

    /// Behind, not in front — in front it would be a stain over its subject.
    @Test("a shadow is drawn behind its subject")
    func shadowIsBehind() {
        let out = ShadowFilter().apply(to: subject(), in: context(ShadowFilter.descriptor))
        #expect(out[0].id.contains("shadow"))
        #expect(out[1].id == "s")
    }

    /// A sprite that travels has to take its shadow with it, or the shadow
    /// stays behind at the starting point.
    @Test("a shadow follows a moving subject")
    func shadowFollowsMovement() throws {
        let out = ShadowFilter().apply(to: subject(moving: true), in: context(
            ShadowFilter.descriptor,
            [ShadowFilter.Param.offsetX: .number(10), ShadowFilter.Param.offsetY: .number(0)],
        ))

        let move = out[0].commands.first { $0.kind == .move }
        let command = try #require(move)
        if case let .move(startX, _, endX, _) = command.payload {
            #expect(startX == 110)
            #expect(endX == 410)
        } else {
            Issue.record("expected a move")
        }
    }

    // ─── Wiggle ──────────────────────────────────────────────────────────────

    @Test("a wiggle adds no sprites")
    func wiggleCostsNothing() {
        let out = WiggleFilter().apply(to: subject(), in: context(WiggleFilter.descriptor))
        #expect(out.count == 1)
    }

    @Test("a wiggle writes movement")
    func wiggleMoves() {
        let out = WiggleFilter().apply(to: subject(), in: context(WiggleFilter.descriptor))
        #expect(out[0].commands.contains { $0.kind == .move })
    }

    /// Seeded, or the preview and the exported file disagree — and the
    /// disagreement only shows once the file has shipped.
    @Test("a wiggle repeats exactly")
    func wiggleIsReproducible() {
        func run() -> [Double] {
            WiggleFilter()
                .apply(to: subject(), in: context(WiggleFilter.descriptor))[0]
                .commands.compactMap { command in
                    if case let .move(startX, _, _, _) = command.payload { return startX }
                    return nil
                }
        }

        #expect(run() == run())
    }

    /// Every step is a command in the file, so a long clip at a high frequency
    /// has to stop somewhere.
    @Test("a wiggle is capped")
    func wiggleIsCapped() {
        var sprites = subject()
        sprites[0].commands = [Command(
            easing: .linear, startTime: 0, endTime: 600_000, payload: .fade(start: 1, end: 1),
        )]

        let out = WiggleFilter().apply(to: sprites, in: context(
            WiggleFilter.descriptor, [WiggleFilter.Param.frequency: .number(20)],
        ))

        #expect(out[0].commands.filter { $0.kind == .move }.count <= 60)
    }

    @Test("all three leave a still clip alone when turned off")
    func zeroedFiltersDoNothing() {
        let flat = subject()
        let wiggled = WiggleFilter().apply(to: flat, in: context(
            WiggleFilter.descriptor, [WiggleFilter.Param.amount: .number(0)],
        ))
        let shadowed = ShadowFilter().apply(to: flat, in: context(
            ShadowFilter.descriptor, [ShadowFilter.Param.opacity: .number(0)],
        ))

        #expect(wiggled[0].commands.count == flat[0].commands.count)
        #expect(shadowed.count == 1)
    }
}
