import Foundation
import StoryboardTestSupport
import Testing

@testable import StoryboardCore

@Suite("Lens Flare")
struct LensFlareFilterTests {
    private func context(_ values: [String: EffectValue] = [:]) -> FilterContext {
        FilterContext(
            descriptor: LensFlareFilter.descriptor,
            node: FilterNode(id: "f", type: "lens-flare", values: LensFlareFilter.descriptor.defaultValues.merging(values) { _, new in new }),
        )
    }

    private func light(x: Double = 120, y: Double = 100, moves: [Command] = []) -> StoryboardSprite {
        StoryboardSprite(
            id: "sun", layer: .foreground, origin: .centre, filePath: "a.png", defaultX: x, defaultY: y,
            commands: [Command(easing: .linear, startTime: 0, endTime: 2000, payload: .fade(start: 1, end: 1))] + moves,
        )
    }

    private func state(_ sprite: StoryboardSprite, _ time: Double) -> SpriteRenderState {
        StoryboardResolver.state(of: StoryboardResolver.prepare([sprite])[0], at: time)
    }

    @Test("the elements sit on the line from the light through the centre")
    func collinear() {
        let out = LensFlareFilter().apply(to: [light()], in: context([LensFlareFilter.Param.elements: .integer(5)]))
        #expect(out.count == 6)
        #expect(out.last?.id == "sun", "the light stays on top")
        let centre = (x: StageSnap.Stage.centreX, y: StageSnap.Stage.centreY)
        for element in out.dropLast() {
            let p = state(element, 1000)
            // Cross product of (light→centre) and (light→element) is zero.
            let cross = (centre.x - 120) * (p.y - 100) - (centre.y - 100) * (p.x - 120)
            #expect(abs(cross) < 1e-6)
            #expect(element.commands.contains { if case .parameter(.additive) = $0.payload { true } else { false } })
        }
    }

    @Test("they reach past the centre, mirrored to the far side")
    func pastCentre() {
        let out = LensFlareFilter().apply(to: [light()], in: context([LensFlareFilter.Param.reach: .number(2)]))
        let farthest = out.dropLast().map { state($0, 1000).x }.max()!
        #expect(abs(farthest - (120 + (320 - 120) * 2)) < 1e-6)
    }

    @Test("a moving light swings its flare the other way")
    func followsTheLight() {
        let moving = light(moves: [Command(easing: .linear, startTime: 0, endTime: 2000, payload: .move(startX: 120, startY: 100, endX: 220, endY: 100))])
        let out = LensFlareFilter().apply(to: [moving], in: context([LensFlareFilter.Param.reach: .number(2)]))
        let far = out.dropLast().max { state($0, 0).x < state($1, 0).x }!
        #expect(state(far, 2000).x < state(far, 0).x, "light goes right, its mirror goes left")
        #expect(out.flatMap(CommandOverlapGuard.violations).isEmpty)
    }

    @Test("it fades with the light")
    func fadesWithTheLight() {
        var fading = light()
        fading.commands = [Command(easing: .linear, startTime: 0, endTime: 2000, payload: .fade(start: 1, end: 0))]
        let out = LensFlareFilter().apply(to: [fading], in: context([LensFlareFilter.Param.intensity: .number(1)]))
        let element = out[0]
        #expect(state(element, 1000).opacity < state(element, 0).opacity)
        #expect(state(element, 2000).opacity < 0.01)
    }

    @Test("a clip of many sprites flares only as many as the cap allows")
    func capped() {
        let many = (0..<500).map { index -> StoryboardSprite in
            var sprite = light()
            sprite.id = "s\(index)"
            return sprite
        }
        let out = LensFlareFilter().apply(to: many, in: context())
        #expect(out.count - 500 <= LensFlareFilter.maximumElements)
    }
}
