import Foundation
import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// The canvas tools see the clip through the storyboard camera, and the model
/// stores it before the camera. Reported on a real project with a rolling,
/// zooming camera: the grip sat beside the clip instead of on it.
@MainActor
@Suite("Canvas drag through the camera")
struct CanvasDragCameraTests {
    /// A shell with one clip at (400, 300) and a zoomed camera.
    private func zoomed() -> (EditorShellModel, EffectNode) {
        let shell = EditorShellModel()
        let node = shell.addEffect(ShapeEffect.descriptor, at: 0, duration: 4000)
        shell.setTransformValue(400, for: .x, on: node.id)
        shell.setTransformValue(300, for: .y, on: node.id)
        shell.setCameraValue(2, for: .zoom)
        shell.playheadTime = 1000
        return (shell, node)
    }

    @Test("the grip sits where the camera draws the clip")
    func originIsProjected() throws {
        let (shell, _) = zoomed()
        let origin = try #require(shell.clipOrigin)
        // Zoom 2 about the camera's look-at (320, 240): 400 → 480, 300 → 360.
        #expect(abs(origin.x - 480) < 0.001 && abs(origin.y - 360) < 0.001, "got \(origin)")
    }

    @Test("a drag on screen moves the clip by what the camera shows")
    func dragIsUnprojected() throws {
        let (shell, node) = zoomed()
        shell.applyCanvasDrag(dx: 40, dy: 0, scaleX: 1, scaleY: 1, isFinished: true, at: 1000)
        let moved = try #require(shell.effects[node.id])
        // Forty points on screen at zoom 2 is twenty in the lane.
        #expect(abs(moved.transform[value: .x] - 420) < 0.001, "got \(moved.transform[value: .x])")
    }

    @Test("a lane fixed to the screen is not projected")
    func fixedLaneIsNotProjected() throws {
        let (shell, node) = zoomed()
        let track = try #require(shell.effects.trackID(of: node.id))
        shell.setFollowsCamera(false, on: track)
        let origin = try #require(shell.clipOrigin)
        #expect(origin.x == 400 && origin.y == 300)
    }

    /// While the camera is edited the canvas shows the world before it, so
    /// the clip is drawn where it is stored.
    @Test("editing the camera shows the clip unprojected")
    func cameraModeIsNotProjected() throws {
        let (shell, _) = zoomed()
        shell.isEditingCamera = true
        let origin = try #require(shell.clipOrigin)
        #expect(origin.x == 400 && origin.y == 300)
    }
}
