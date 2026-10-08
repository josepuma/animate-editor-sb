import Foundation
import Testing

@testable import StoryboardCore

/// The 3D filters: Card Flip, Carousel and Extrude — depth faked with what a
/// sprite can do, read back through the resolver that draws it.
@Suite("3D filters")
struct DepthFilterTests {
    private func context(
        _ filter: FilterDescriptor, _ values: [String: EffectValue] = [:], transform: Transform = Transform(),
    ) -> FilterContext {
        FilterContext(
            descriptor: filter,
            node: FilterNode(id: "f", type: filter.type, values: filter.defaultValues.merging(values) { _, new in new }),
            transform: transform,
        )
    }

    private func sprite(id: String = "s", x: Double = 320, y: Double = 240, end: Double = 3000) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: "a.png", defaultX: x, defaultY: y,
            commands: [Command(easing: .linear, startTime: 0, endTime: end, payload: .fade(start: 1, end: 1))],
        )
    }

    private func state(_ sprite: StoryboardSprite, _ time: Double) -> SpriteRenderState {
        StoryboardResolver.state(of: StoryboardResolver.prepare([sprite])[0], at: time)
    }

    /// One half-turn, so the far side is where the test can see it.
    private let flipValues: [String: EffectValue] = [
        CardFlipFilter.Param.turns: .number(1),
        CardFlipFilter.Param.start: .number(1000),
        CardFlipFilter.Param.duration: .number(1000),
        CardFlipFilter.Param.easing: .choice(CardFlipFilter.Curve.linear.rawValue),
    ]

    // MARK: - Card Flip

    @Test("a card turns edge-on halfway and lands showing its back")
    func cardFlipHalf() {
        let out = CardFlipFilter().apply(to: [sprite()], in: context(CardFlipFilter.descriptor, flipValues))[0]
        #expect(abs(state(out, 500).scaleX - 1) < 1e-6, "untouched before the flip")
        #expect(abs(state(out, 1500).scaleX) < 0.02, "edge-on at 90°")
        #expect(abs(state(out, 1250).scaleX - cos(.pi / 4)) < 0.02)
        let end = state(out, 2500)
        #expect(abs(end.scaleX - 1) < 1e-6)
        #expect(end.flipH, "one half-turn ends on the back")
        #expect(!state(out, 1200).flipH && state(out, 1800).flipH)
    }

    @Test("two half-turns end facing front again")
    func cardFlipFull() {
        var values = flipValues
        values[CardFlipFilter.Param.turns] = .number(2)
        let out = CardFlipFilter().apply(to: [sprite()], in: context(CardFlipFilter.descriptor, values))[0]
        #expect(!state(out, 2500).flipH)
        #expect(state(out, 1500).flipH, "it passes its back on the way")
    }

    @Test("the X axis turns the card over its height instead")
    func cardFlipAxisX() {
        var values = flipValues
        values[CardFlipFilter.Param.axis] = .choice(CardFlipFilter.Axis.x.rawValue)
        let out = CardFlipFilter().apply(to: [sprite()], in: context(CardFlipFilter.descriptor, values))[0]
        let mid = state(out, 1500)
        #expect(abs(mid.scaleY) < 0.02 && abs(mid.scaleX - 1) < 1e-6)
        #expect(state(out, 2500).flipV)
    }

    @Test("as a group, positions turn about the clip's pivot")
    func cardFlipGroup() {
        var values = flipValues
        values[CardFlipFilter.Param.mode] = .choice(CardFlipFilter.Mode.group.rawValue)
        var transform = Transform()
        transform[value: .x] = 320
        let out = CardFlipFilter().apply(
            to: [sprite(x: 420), sprite(id: "b", x: 320)],
            in: context(CardFlipFilter.descriptor, values, transform: transform),
        )
        #expect(abs(state(out[0], 2500).x - 220) < 0.5, "mirrored across the pivot")
        #expect(abs(state(out[0], 1500).x - 320) < 2, "edge-on, everything on the axis")
        #expect(abs(state(out[1], 2500).x - 320) < 1e-6)
    }

    @Test("the card keeps its own size")
    func cardFlipKeepsSize() {
        var sized = sprite()
        sized.commands.append(Command(easing: .linear, startTime: 0, endTime: 0, payload: .scale(start: 2, end: 2)))
        let out = CardFlipFilter().apply(to: [sized], in: context(CardFlipFilter.descriptor, flipValues))[0]
        #expect(abs(state(out, 2500).scaleX - 2) < 1e-6)
        #expect(abs(state(out, 1250).scaleX - 2 * cos(.pi / 4)) < 0.05)
        #expect(!out.commands.contains { $0.kind == .scale }, "no _S beside the _V")
    }

    // MARK: - Carousel

    private let carousel: [String: EffectValue] = [
        CarouselFilter.Param.radius: .number(200),
        CarouselFilter.Param.spin: .number(90),
        CarouselFilter.Param.perspective: .number(0.4),
        CarouselFilter.Param.backFade: .number(0.5),
    ]

    @Test("a sprite at the centre starts at the front, full size")
    func carouselFront() {
        let out = CarouselFilter().apply(to: [sprite()], in: context(CarouselFilter.descriptor, carousel))[0]
        let front = state(out, 0)
        #expect(abs(front.x - 320) < 1e-6)
        #expect(abs(front.scaleX - 1) < 1e-6 && abs(front.scaleY - 1) < 1e-6)
    }

    @Test("spin carries it round: edge-on at the side, dim and mirrored at the back")
    func carouselTurns() {
        let out = CarouselFilter().apply(to: [sprite(end: 3000)], in: context(CarouselFilter.descriptor, carousel))[0]
        let side = state(out, 1000)
        #expect(abs(side.x - 520) < 1, "90° round is the rim")
        #expect(abs(side.scaleX) < 0.05)
        let back = state(out, 2000)
        #expect(abs(back.x - 320) < 1)
        #expect(back.flipH)
        #expect(abs(back.opacity - 0.5) < 0.02)
        // Further away reads smaller: perspective 0.4 at the back.
        #expect(abs(back.scaleY - 0.6) < 0.02)
    }

    /// The drum's crossings are not sample points, so which way an interval
    /// faces has to be read inside it: read at its start, the back shows a
    /// whole sample late, right past the rim.
    @Test("the back shows as soon as it passes the rim")
    func carouselFlipsOnTime() {
        let out = CarouselFilter().apply(to: [sprite(end: 3000)], in: context(CarouselFilter.descriptor, carousel))[0]
        #expect(!state(out, 950).flipH)
        #expect(state(out, 1050).flipH)
    }

    @Test("a line wraps round the cylinder by its x")
    func carouselWraps() {
        let still = carousel.merging([CarouselFilter.Param.spin: .number(0)]) { _, new in new }
        let edge = 320 + 200 * Double.pi / 2
        let out = CarouselFilter().apply(to: [sprite(x: edge)], in: context(CarouselFilter.descriptor, still))[0]
        #expect(abs(state(out, 0).x - 520) < 1)
    }

    // MARK: - Extrude

    @Test("extrude stacks copies behind, stepping away and darkening")
    func extrudeStacks() {
        let values: [String: EffectValue] = [
            ExtrudeFilter.Param.steps: .integer(4), ExtrudeFilter.Param.depth: .number(20), ExtrudeFilter.Param.angle: .number(0),
            ExtrudeFilter.Param.colour: .color(EffectColor(r: 200, g: 100, b: 0)), ExtrudeFilter.Param.shade: .number(0.5),
        ]
        let out = ExtrudeFilter().apply(to: [sprite()], in: context(ExtrudeFilter.descriptor, values))
        #expect(out.count == 5)
        #expect(out.last?.filePath == "a.png" && out.last?.defaultX == 320, "the face stays on top, unmoved")
        // Back to front: the farthest copy draws first.
        #expect(out.dropLast().map(\.defaultX) == [340, 335, 330, 325])
        let reds = out.dropLast().compactMap { sprite -> Double? in
            sprite.commands.compactMap { if case let .color(r, _, _, _, _, _) = $0.payload { r } else { nil } }.first
        }
        #expect(reds == [100, 125, 150, 175])
    }

    @Test("its cost is the steps plus the face")
    func extrudeCost() {
        let filter = ExtrudeFilter()
        #expect(filter.estimatedMultiplier(in: context(ExtrudeFilter.descriptor, [ExtrudeFilter.Param.steps: .integer(6)])) == 7)
    }

    @Test("a moving face drags its extrusion with it")
    func extrudeMoves() {
        var moving = sprite()
        moving.commands.append(Command(easing: .linear, startTime: 0, endTime: 1000, payload: .move(startX: 0, startY: 0, endX: 100, endY: 0)))
        let out = ExtrudeFilter().apply(
            to: [moving],
            in: context(ExtrudeFilter.descriptor, [ExtrudeFilter.Param.steps: .integer(1), ExtrudeFilter.Param.depth: .number(10), ExtrudeFilter.Param.angle: .number(90)]),
        )
        #expect(abs(state(out[0], 500).x - 50) < 1e-6)
        #expect(abs(state(out[0], 500).y - 10) < 1e-6)
    }
}
