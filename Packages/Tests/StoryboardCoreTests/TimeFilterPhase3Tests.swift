import Foundation
import Testing

@testable import StoryboardCore

/// Stagger and Posterize Time.
@Suite("Time filters: Stagger and Posterize")
struct TimeFilterPhase3Tests {
    private func context(_ filter: FilterDescriptor, _ values: [String: EffectValue] = [:]) -> FilterContext {
        FilterContext(
            descriptor: filter,
            node: FilterNode(id: "f", type: filter.type, values: filter.defaultValues.merging(values) { _, new in new }),
        )
    }

    private func sprite(_ id: String, x: Double = 320, y: Double = 240, start: Double = 0, end: Double = 1000) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: "a.png", defaultX: x, defaultY: y,
            commands: [
                Command(easing: .linear, startTime: start, endTime: end, payload: .fade(start: 0, end: 1)),
                Command(easing: .quadOut, startTime: start, endTime: end, payload: .move(startX: x, startY: y, endX: x + 300, endY: y)),
            ],
        )
    }

    private func birth(_ sprite: StoryboardSprite) -> Double { sprite.commands.map(\.startTime).min()! }

    private func state(_ sprite: StoryboardSprite, _ time: Double) -> SpriteRenderState {
        StoryboardResolver.state(of: StoryboardResolver.prepare([sprite])[0], at: time)
    }

    // MARK: - Stagger

    @Test("in index order each sprite starts its share of the spread later")
    func staggerIndex() {
        let sprites = (0..<5).map { sprite("s\($0)") }
        let out = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, [StaggerFilter.Param.spread: .number(400)]))
        #expect(out.map(birth) == [0, 100, 200, 300, 400])
        // Everything moves, not just the first command.
        #expect(out[4].commands.allSatisfy { $0.startTime >= 400 })
    }

    @Test("reverse runs the other way")
    func staggerReverse() {
        let sprites = (0..<3).map { sprite("s\($0)") }
        let out = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, [
            StaggerFilter.Param.spread: .number(200), StaggerFilter.Param.order: .choice(StaggerFilter.Order.reverse.rawValue),
        ]))
        #expect(out.map(birth) == [200, 100, 0])
    }

    @Test("left to right orders by where each sprite is, not by index")
    func staggerLeftToRight() {
        let sprites = [sprite("a", x: 500), sprite("b", x: 100), sprite("c", x: 300)]
        let out = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, [
            StaggerFilter.Param.spread: .number(200), StaggerFilter.Param.order: .choice(StaggerFilter.Order.leftToRight.rawValue),
        ]))
        #expect(out.map(birth) == [200, 0, 100])
    }

    @Test("from the centre outward")
    func staggerFromCentre() {
        let sprites = [sprite("far", x: 700), sprite("near", x: 330), sprite("mid", x: 500)]
        let out = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, [
            StaggerFilter.Param.spread: .number(200), StaggerFilter.Param.order: .choice(StaggerFilter.Order.fromCentre.rawValue),
        ]))
        #expect(out.map(birth) == [200, 0, 100])
    }

    @Test("random is a shuffle, the same every time")
    func staggerRandom() {
        let sprites = (0..<8).map { sprite("s\($0)") }
        let values: [String: EffectValue] = [
            StaggerFilter.Param.spread: .number(700), StaggerFilter.Param.order: .choice(StaggerFilter.Order.random.rawValue),
        ]
        let a = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, values)).map(birth)
        let b = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, values)).map(birth)
        #expect(a == b)
        #expect(Set(a) == Set((0..<8).map { Double($0) * 100 }))
        #expect(a != a.sorted())
    }

    /// A clip that keeps playing after the timeline says it ended is one
    /// nobody can line anything up against.
    @Test("the clip runs on by the spread")
    func staggerDuration() {
        let filter = StaggerFilter()
        #expect(filter.duration(of: 2000, in: context(StaggerFilter.descriptor, [StaggerFilter.Param.spread: .number(600)])) == 2600)
        #expect(filter.duration(of: 2000, in: context(StaggerFilter.descriptor, [StaggerFilter.Param.spread: .number(0)])) == 2000)
    }

    @Test("zero spread changes nothing")
    func staggerInert() {
        let sprites = [sprite("a"), sprite("b")]
        let out = StaggerFilter().apply(to: sprites, in: context(StaggerFilter.descriptor, [StaggerFilter.Param.spread: .number(0)]))
        #expect(out.map(birth) == [0, 0])
    }

    // MARK: - Posterize Time

    @Test("movement holds between frames and jumps on them")
    func posterizeHolds() {
        let original = sprite("s")
        let out = PosterizeTimeFilter().apply(to: [original], in: context(PosterizeTimeFilter.descriptor, [PosterizeTimeFilter.Param.fps: .number(10)]))[0]
        // 10 fps: frames every 100ms, aligned to the clip.
        #expect(state(out, 210).x == state(out, 290).x, "held inside a frame")
        #expect(state(out, 290).x != state(out, 310).x, "a jump on the frame")
        // On a frame, the value is the original's.
        for frame in stride(from: 0.0, through: 1000, by: 100) {
            #expect(abs(state(out, frame).x - state(original, frame).x) < 1e-6)
        }
    }

    /// Every sprite steps on the clip's beat, not on its own: a field born
    /// over time would otherwise flicker out of step with itself.
    @Test("frames are on the clip's grid whenever a sprite is born")
    func posterizeSharedGrid() {
        let late = sprite("s", start: 30, end: 1030)
        let out = PosterizeTimeFilter().apply(to: [late], in: context(PosterizeTimeFilter.descriptor, [PosterizeTimeFilter.Param.fps: .number(10)]))[0]
        let starts = Set(out.commands.filter { $0.kind == .move }.map(\.startTime))
        #expect(starts == Set([30.0, 1030] + stride(from: 100.0, through: 1000, by: 100)))
    }

    @Test("fades are left smooth")
    func posterizeKeepsFades() {
        let original = sprite("s")
        let out = PosterizeTimeFilter().apply(to: [original], in: context(PosterizeTimeFilter.descriptor))[0]
        #expect(abs(state(out, 250).opacity - 0.25) < 1e-6)
    }

    @Test("a long life lengthens the frames instead of writing thousands")
    func posterizeCap() {
        let long = sprite("s", end: 600_000)
        let out = PosterizeTimeFilter().apply(to: [long], in: context(PosterizeTimeFilter.descriptor, [PosterizeTimeFilter.Param.fps: .number(24)]))[0]
        let moves = out.commands.filter { $0.kind == .move }
        #expect(moves.count <= PosterizeTimeFilter.maximumFrames + 1)
        #expect(abs(state(out, 600_000).x - state(long, 600_000).x) < 1e-6, "it still lands where the sprite does")
    }

    @Test("a still sprite is left alone")
    func posterizeStill() {
        let still = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "a.png", defaultX: 1, defaultY: 2,
            commands: [Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 1, end: 1))],
        )
        let out = PosterizeTimeFilter().apply(to: [still], in: context(PosterizeTimeFilter.descriptor))[0]
        #expect(out.commands.count == 1)
    }
}
