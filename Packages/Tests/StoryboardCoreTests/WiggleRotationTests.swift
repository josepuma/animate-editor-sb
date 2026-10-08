import Foundation
import Testing

@testable import StoryboardCore

/// Wiggle's rotation and scale: a sway, not a series of snaps.
///
/// Found on swaying dandelions that "did not turn right": every step began
/// its rotation at a fresh random angle instead of where the last step
/// ended, so each flower snapped to a new lean every second and a half. And
/// the angle was absolute, written beside the sprite's own `_R` — two
/// rotation commands over the same instant fight, the same collision this
/// filter already fixed for movement.
@Suite("Wiggle rotation and scale")
struct WiggleRotationTests {
    private func sprite(_ extra: [Command] = []) -> StoryboardSprite {
        StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "x.png",
            defaultX: 320, defaultY: 240,
            commands: [
                Command(easing: .linear, startTime: 0, endTime: 6000, payload: .fade(start: 1, end: 1)),
            ] + extra,
        )
    }

    private func wiggled(_ sprite: StoryboardSprite, rotation: Double = 0, scale: Double = 0) -> StoryboardSprite {
        let node = FilterNode(id: "w", type: WiggleFilter.descriptor.type, values: [
            WiggleFilter.Param.amount: .number(0),
            WiggleFilter.Param.frequency: .number(2),
            WiggleFilter.Param.rotation: .number(rotation),
            WiggleFilter.Param.scale: .number(scale),
        ])
        let context = FilterContext(descriptor: WiggleFilter.descriptor, node: node)
        return WiggleFilter().apply(to: [sprite], in: context)[0]
    }

    private func state(_ sprite: StoryboardSprite, at time: Double) -> SpriteRenderState {
        let prepared = StoryboardResolver.prepare([sprite])
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: time, into: &states)
        return states[0]
    }

    private func commands(_ sprite: StoryboardSprite, _ kind: CommandKind) -> [Command] {
        sprite.commands.filter { $0.kind == kind }.sorted { $0.startTime < $1.startTime }
    }

    @Test("a wiggled rotation never jumps between steps")
    func rotationIsContinuous() {
        let rotations = commands(wiggled(sprite(), rotation: 10), .rotate)
        #expect(rotations.count > 3)
        for (a, b) in zip(rotations, rotations.dropFirst()) {
            guard case let .rotate(_, end) = a.payload, case let .rotate(start, _) = b.payload else { continue }
            #expect(abs(end - start) < 1e-9, "the rotation snaps \(end) → \(start) at \(b.startTime)")
        }
    }

    @Test("a wiggled scale never jumps between steps")
    func scaleIsContinuous() {
        let scales = commands(wiggled(sprite(), scale: 0.2), .scale)
        #expect(scales.count > 3)
        for (a, b) in zip(scales, scales.dropFirst()) {
            guard case let .scale(_, end) = a.payload, case let .scale(start, _) = b.payload else { continue }
            #expect(abs(end - start) < 1e-9, "the scale snaps \(end) → \(start) at \(b.startTime)")
        }
    }

    /// A sway is around the lean the sprite already has — a seed tilted by
    /// its emitter, a head set at an angle — not around zero.
    @Test("a wiggle sways about the sprite's own rotation")
    func swaysAboutOwnRotation() {
        let tilted = sprite([Command(easing: .linear, startTime: 0, endTime: 0, payload: .rotate(start: 1, end: 1))])
        let result = wiggled(tilted, rotation: 10)
        let limit = 10 * Double.pi / 180 + 1e-6
        for time in stride(from: 100.0, through: 5900, by: 100) {
            #expect(abs(state(result, at: time).rotation - 1) <= limit, "at \(time) the lean is \(state(result, at: time).rotation)")
        }
    }

    /// And around a spin, which keeps spinning underneath.
    @Test("a wiggle sways on top of a spin")
    func swaysOnTopOfSpin() {
        let spinning = sprite([Command(easing: .linear, startTime: 0, endTime: 6000, payload: .rotate(start: 0, end: 3))])
        let result = wiggled(spinning, rotation: 10)
        let limit = 10 * Double.pi / 180 + 1e-6
        for time in stride(from: 100.0, through: 5900, by: 100) {
            let base = 3 * time / 6000
            #expect(abs(state(result, at: time).rotation - base) <= limit, "at \(time) it is off its spin")
        }
    }

    /// One description of the angle at a time: rotation commands that overlap
    /// fight, and osu! shows one of them.
    @Test("a wiggle leaves no overlapping rotation")
    func noOverlappingRotation() {
        let spinning = sprite([Command(easing: .linear, startTime: 0, endTime: 6000, payload: .rotate(start: 0, end: 3))])
        let rotations = commands(wiggled(spinning, rotation: 10), .rotate)
        for (a, b) in zip(rotations, rotations.dropFirst()) {
            #expect(b.startTime >= a.endTime - 1e-9, "rotations overlap at \(b.startTime)")
        }
    }

    /// A scale wobble is a factor on the size the sprite already has.
    @Test("a wiggle scales about the sprite's own size")
    func scalesAboutOwnSize() {
        let half = sprite([Command(easing: .linear, startTime: 0, endTime: 0, payload: .scale(start: 0.5, end: 0.5))])
        let result = wiggled(half, scale: 0.2)
        for time in stride(from: 100.0, through: 5900, by: 100) {
            let size = state(result, at: time).scaleX
            #expect(size >= 0.5 * 0.8 - 1e-6 && size <= 0.5 * 1.2 + 1e-6, "at \(time) the size is \(size)")
        }
        for (a, b) in zip(commands(result, .scale), commands(result, .scale).dropFirst()) {
            #expect(b.startTime >= a.endTime - 1e-9, "scales overlap at \(b.startTime)")
        }
    }
}
