import Foundation
import Testing

@testable import StoryboardCore

/// Where a point of a lane lands on screen, and how far a drag on screen moves
/// it — for the editor's tools, which see the picture *after* the camera.
///
/// The canvas measures the selection box on what is drawn, through the
/// camera; the clip's position is stored before it. Without projecting, the
/// grip sat away from the clip on any project with a camera, and a drag moved
/// the clip in the wrong direction under a roll and by the wrong amount under
/// a zoom or on a lane with depth.
@Suite("Camera projection")
struct CameraProjectionTests {
    private func camera() -> StoryboardCamera {
        var camera = StoryboardCamera()
        camera[.x] = KeyframeTrack([Keyframe(time: 0, value: 360, easing: .linear)])
        camera[.y] = KeyframeTrack([Keyframe(time: 0, value: 220, easing: .linear)])
        camera[.zoom] = KeyframeTrack([
            Keyframe(time: 0, value: 1.5, easing: .linear),
            Keyframe(time: 2000, value: 2.5, easing: .linear),
        ])
        camera[.rotation] = KeyframeTrack([Keyframe(time: 0, value: 20, easing: .linear)])
        return camera
    }

    /// The projection has to agree with the bake, or the grip sits somewhere
    /// the sprite is not.
    @Test("a projected point is where the bake draws a sprite", arguments: [0.0, 400.0])
    func projectionMatchesTheBake(z: Double) throws {
        let sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre, filePath: "sb/dot.png",
            defaultX: 400, defaultY: 300,
            commands: [Command(easing: .linear, startTime: 0, endTime: 2000, payload: .fade(start: 1, end: 1))],
        )
        let baked = CameraTransform.apply(camera(), to: [sprite], z: z)
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(baked), at: 1000, into: &states)
        let drawn = try #require(states.first)

        let projected = CameraTransform.project(400, 300, through: camera(), at: 1000, z: z)

        #expect(abs(projected.x - drawn.x) < 0.01, "x \(projected.x) against \(drawn.x)")
        #expect(abs(projected.y - drawn.y) < 0.01, "y \(projected.y) against \(drawn.y)")
    }

    /// A drag measured on screen, taken back into the lane, has to land the
    /// point exactly that far along on screen.
    @Test("an unprojected drag moves the point by that drag on screen", arguments: [0.0, 400.0])
    func unprojectedDragRoundTrips(z: Double) {
        let camera = camera()
        let before = CameraTransform.project(400, 300, through: camera, at: 1000, z: z)
        let travel = CameraTransform.unproject(dx: 50, dy: -30, through: camera, at: 1000, z: z)
        let after = CameraTransform.project(400 + travel.dx, 300 + travel.dy, through: camera, at: 1000, z: z)

        #expect(abs(after.x - before.x - 50) < 0.001)
        #expect(abs(after.y - before.y + 30) < 0.001)
    }

    @Test("a camera at rest projects a lane at depth zero to itself")
    func restIsIdentity() {
        let point = CameraTransform.project(123, 456, through: StoryboardCamera(), at: 0, z: 0)
        #expect(point.x == 123 && point.y == 456)
        let travel = CameraTransform.unproject(dx: 7, dy: -9, through: StoryboardCamera(), at: 0, z: 0)
        #expect(travel.dx == 7 && travel.dy == -9)
    }
}
