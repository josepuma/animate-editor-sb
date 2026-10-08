import Foundation
import Testing

@testable import StoryboardCore

/// The Look filters: Outline, Halftone, Duotone, Ink and Hue Cycle.
///
/// Four of them change the image a sprite draws, through a derived path the
/// renderer reads back. Core writes the path and the renderer parses it, so
/// the round trip is the contract — a disagreement leaves a sprite naming an
/// image nobody makes, which draws as a bare quad with nothing to explain it.
@Suite("Look filter paths")
struct LookFilterPathTests {
    @Test("an outline path round-trips, its width quantised to whole pixels")
    func outlinePath() throws {
        let path = DerivedSprite.outlined("sb/a.png", width: 4.4)
        #expect(path == "__derived__/outline4/sb/a.png")
        let parsed = try #require(DerivedSprite.parse(path))
        #expect(parsed.kind == .outline(width: 4))
        #expect(parsed.source == "sb/a.png")
    }

    @Test("an outline is at least a pixel and at most the cap")
    func outlineClamps() {
        #expect(DerivedSprite.outlined("a.png", width: 0) == "__derived__/outline1/a.png")
        #expect(DerivedSprite.outlined("a.png", width: 999).hasPrefix("__derived__/outline\(DerivedSprite.outlineWidthRange.upperBound)/"))
    }

    @Test("the canvas an outline grows by covers the outline and its antialiasing")
    func outlineMargin() {
        #expect(DerivedSprite.outlineMargin(width: 4) == 5)
    }

    @Test("a halftone path round-trips")
    func halftonePath() throws {
        let path = DerivedSprite.halftone("sb/a.png", cell: 9.6, shape: .square)
        #expect(path == "__derived__/halftone10-s/sb/a.png")
        let parsed = try #require(DerivedSprite.parse(path))
        #expect(parsed.kind == .halftone(cell: 10, shape: .square))
    }

    @Test("a duotone path round-trips, each colour as six hex digits")
    func duotonePath() throws {
        let path = DerivedSprite.duotone(
            "__text__/x.png",
            dark: EffectColor(r: 20, g: 0, b: 255),
            light: EffectColor(r: 255, g: 200.4, b: 16),
        )
        #expect(path == "__derived__/duo1400ff-ffc810/__text__/x.png")
        let parsed = try #require(DerivedSprite.parse(path))
        #expect(parsed.kind == .duotone(dark: 0x1400FF, light: 0xFFC810))
        #expect(parsed.source == "__text__/x.png")
    }

    @Test("an ink path round-trips")
    func inkPath() throws {
        let path = DerivedSprite.inked("a.png", width: 2.2, detail: 0.35)
        #expect(path == "__derived__/ink2-35/a.png")
        let parsed = try #require(DerivedSprite.parse(path))
        #expect(parsed.kind == .ink(width: 2, detailPercent: 35))
    }

    /// Derivations stack: a glow over an outline names the outline as its
    /// source, and the renderer resolves the inner path first.
    @Test("a derived path can name another derived path as its source")
    func nested() throws {
        let inner = DerivedSprite.outlined("a.png", width: 3)
        let outer = DerivedSprite.blurred(inner, radius: 4)
        let parsed = try #require(DerivedSprite.parse(outer))
        #expect(parsed.source == inner)
    }
}

/// What each filter writes, read off the sprites it returns.
@Suite("Look filters")
struct LookFilterTests {
    // MARK: - Helpers

    private func context(_ filter: FilterDescriptor, _ values: [String: EffectValue] = [:]) -> FilterContext {
        FilterContext(
            descriptor: filter,
            node: FilterNode(
                id: "f", type: filter.type,
                values: filter.defaultValues.merging(values) { _, new in new },
            ),
        )
    }

    private func sprite(
        origin: Origin = .centre,
        commands: [Command] = [
            Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 0, end: 1)),
        ],
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: "s", layer: .foreground, origin: origin, filePath: "sb/a.png",
            defaultX: 320, defaultY: 240, commands: commands,
        )
    }

    // MARK: - Outline

    @Test("an outline is one copy behind each sprite, drawing the outlined image")
    func outlineCopiesBehind() {
        let out = OutlineFilter().apply(to: [sprite(), sprite()], in: context(OutlineFilter.descriptor))
        #expect(out.count == 4)
        #expect(out[0].filePath.hasPrefix("__derived__/outline"))
        #expect(out[1].filePath.hasPrefix("__derived__/outline"))
        #expect(out[2].filePath == "sb/a.png", "the originals stay on top")
        #expect(out[0].id != out[2].id)
    }

    @Test("the outline takes its own colour, not the sprite's")
    func outlineColour() {
        let red = Command(easing: .linear, startTime: 0, endTime: 0, payload: .color(
            startR: 255, startG: 0, startB: 0, endR: 255, endG: 0, endB: 0,
        ))
        let out = OutlineFilter().apply(
            to: [sprite(commands: sprite().commands + [red])],
            in: context(OutlineFilter.descriptor, [OutlineFilter.Param.colour: .color(EffectColor(r: 0, g: 10, b: 20))]),
        )
        let colours = out[0].commands.compactMap { command -> Double? in
            if case let .color(_, g, _, _, _, _) = command.payload { return g }
            return nil
        }
        #expect(colours == [10])
    }

    /// An outline is paint, not light: an additive black adds nothing.
    @Test("the outline is never additive, even when its sprite is")
    func outlineNotAdditive() {
        let additive = Command(easing: .linear, startTime: 0, endTime: 1000, payload: .parameter(.additive))
        let out = OutlineFilter().apply(
            to: [sprite(commands: sprite().commands + [additive])],
            in: context(OutlineFilter.descriptor),
        )
        #expect(!out[0].commands.contains { $0.kind == .parameter })
    }

    /// The outlined image is bigger than its source by a margin each side, and
    /// osu! anchors the bigger canvas — so a sprite hung from its top-left
    /// corner would draw its outline a margin up and left of the original.
    @Test("a centred sprite's outline sits where the sprite does")
    func outlineCentred() {
        let out = OutlineFilter().apply(to: [sprite()], in: context(OutlineFilter.descriptor))
        #expect(out[0].defaultX == 320)
        #expect(out[0].defaultY == 240)
    }

    @Test("an anchored sprite's outline is moved back by the margin, at the sprite's scale", arguments: [
        (Origin.topLeft, -1.0, -1.0), (.bottomRight, 1.0, 1.0), (.topCentre, 0.0, -1.0), (.centreLeft, -1.0, 0.0),
    ])
    func outlineAnchored(_ origin: Origin, _ dx: Double, _ dy: Double) {
        let scaled = sprite(origin: origin, commands: sprite().commands + [
            Command(easing: .linear, startTime: 0, endTime: 0, payload: .vectorScale(startX: 2, startY: 3, endX: 2, endY: 3)),
        ])
        let out = OutlineFilter().apply(
            to: [scaled],
            in: context(OutlineFilter.descriptor, [OutlineFilter.Param.width: .number(4)]),
        )
        let margin = Double(DerivedSprite.outlineMargin(width: 4))
        #expect(abs(out[0].defaultX - (320 + dx * margin * 2)) < 1e-9)
        #expect(abs(out[0].defaultY - (240 + dy * margin * 3)) < 1e-9)
    }

    @Test("the correction follows a moving sprite")
    func outlineMoves() throws {
        let moving = sprite(origin: .topLeft, commands: sprite().commands + [
            Command(easing: .linear, startTime: 0, endTime: 1000, payload: .move(startX: 0, startY: 0, endX: 100, endY: 50)),
        ])
        let out = OutlineFilter().apply(
            to: [moving],
            in: context(OutlineFilter.descriptor, [OutlineFilter.Param.width: .number(4)]),
        )
        let move = try #require(out[0].commands.first { $0.kind == .move })
        let margin = Double(DerivedSprite.outlineMargin(width: 4))
        #expect(same(move.payload, .move(startX: -margin, startY: -margin, endX: 100 - margin, endY: 50 - margin)))
    }

    @Test("zero opacity draws no outline")
    func outlineOff() {
        let out = OutlineFilter().apply(
            to: [sprite()],
            in: context(OutlineFilter.descriptor, [OutlineFilter.Param.opacity: .number(0)]),
        )
        #expect(out.count == 1)
    }

    // MARK: - Image swaps

    @Test("halftone, duotone and ink change the image and add no sprites")
    func swaps() {
        let halftone = HalftoneFilter().apply(to: [sprite()], in: context(HalftoneFilter.descriptor))
        #expect(halftone.map(\.filePath) == [DerivedSprite.halftone("sb/a.png", cell: 8, shape: .round)])

        let duotone = DuotoneFilter().apply(to: [sprite()], in: context(DuotoneFilter.descriptor))
        #expect(duotone.count == 1)
        #expect(duotone[0].filePath.hasPrefix("__derived__/duo"))

        let ink = InkFilter().apply(to: [sprite()], in: context(InkFilter.descriptor))
        #expect(ink.count == 1)
        #expect(ink[0].filePath.hasPrefix("__derived__/ink"))
        #expect(ink[0].commands.map { "\($0.payload)" } == sprite().commands.map { "\($0.payload)" }, "only the image changes")
    }

    @Test("ink over the original keeps the original and draws the lines on top in their colour")
    func inkOver() {
        let out = InkFilter().apply(
            to: [sprite()],
            in: context(InkFilter.descriptor, [
                InkFilter.Param.mode: .choice(InkFilter.Mode.over.rawValue),
                InkFilter.Param.colour: .color(EffectColor(r: 1, g: 2, b: 3)),
            ]),
        )
        #expect(out.count == 2)
        #expect(out[0].filePath == "sb/a.png")
        #expect(out[1].filePath.hasPrefix("__derived__/ink"))
        #expect(out[1].commands.contains { same($0.payload, .color(startR: 1, startG: 2, startB: 3, endR: 1, endG: 2, endB: 3)) })
    }

    // MARK: - Hue Cycle

    private func hues(_ sprite: StoryboardSprite) -> [Command] {
        sprite.commands.filter { $0.kind == .color }
    }

    /// HSV is piecewise linear in RGB between the six primaries and
    /// secondaries, so a command per sixth of the wheel is exact rather than
    /// an approximation of the ramp.
    @Test("a cycle is written as one colour command per sixth of the wheel")
    func cycleSegments() {
        let out = HueCycleFilter().apply(
            to: [sprite()],
            in: context(HueCycleFilter.descriptor, [
                HueCycleFilter.Param.speed: .number(1),
                HueCycleFilter.Param.spread: .number(0),
                HueCycleFilter.Param.saturation: .number(1),
            ]),
        )
        let colours = hues(out[0])
        #expect(colours.count == 6)
        // Contiguous over the sprite's life.
        #expect(colours.first?.startTime == 0)
        #expect(colours.last?.endTime == 1000)
        for (a, b) in zip(colours, colours.dropFirst()) {
            #expect(a.endTime == b.startTime)
        }
        // Starts on red and comes back to it.
        #expect(same(colours.first?.payload, .color(startR: 255, startG: 0, startB: 0, endR: 255, endG: 255, endB: 0)))
    }

    @Test("the cycle replaces the sprite's own colour")
    func cycleReplaces() {
        let red = Command(easing: .linear, startTime: 0, endTime: 1000, payload: .color(
            startR: 9, startG: 9, startB: 9, endR: 9, endG: 9, endB: 9,
        ))
        let out = HueCycleFilter().apply(
            to: [sprite(commands: sprite().commands + [red])],
            in: context(HueCycleFilter.descriptor),
        )
        #expect(!hues(out[0]).contains { same($0.payload, red.payload) })
        #expect(CommandOverlapCheck.colourOverlaps(out[0]) == 0)
    }

    @Test("spread starts each sprite at a different hue")
    func cycleSpread() {
        let out = HueCycleFilter().apply(
            to: [sprite(), sprite(), sprite()],
            in: context(HueCycleFilter.descriptor, [HueCycleFilter.Param.spread: .number(0.6)]),
        )
        let firsts = out.map { hues($0).first.map { String(describing: $0.payload) } ?? "" }
        #expect(Set(firsts).count == 3)
    }

    @Test("a long life lengthens the steps instead of cutting the cycle short")
    func cycleCap() {
        let long = sprite(commands: [
            Command(easing: .linear, startTime: 0, endTime: 600_000, payload: .fade(start: 1, end: 1)),
        ])
        let out = HueCycleFilter().apply(
            to: [long],
            in: context(HueCycleFilter.descriptor, [HueCycleFilter.Param.speed: .number(4)]),
        )
        let colours = hues(out[0])
        #expect(colours.count <= HueCycleFilter.maximumSteps)
        #expect(colours.last?.endTime == 600_000)
    }
}

/// Payloads are not `Equatable`; their description is exact for these.
private func same(_ a: Command.Payload?, _ b: Command.Payload) -> Bool {
    a.map { String(describing: $0) } == String(describing: b)
}

/// Counts overlapping colour commands — the one family Hue Cycle writes.
private enum CommandOverlapCheck {
    static func colourOverlaps(_ sprite: StoryboardSprite) -> Int {
        let colours = sprite.commands.filter { $0.kind == .color }
        var count = 0
        for i in colours.indices {
            for j in colours.indices where j > i {
                if colours[i].startTime < colours[j].endTime, colours[j].startTime < colours[i].endTime { count += 1 }
            }
        }
        return count
    }
}
