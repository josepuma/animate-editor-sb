import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Where the grip on the canvas is drawn.
///
/// **The bug this pins**: the grip sat at the centre of the selection box,
/// which is right for a sprite and wrong for anything that travels. A radial
/// burst is emitted from a point and its box is the whole spray — measured on
/// the `warp` preset, 2173px wide against an 854px stage, centred 109px below
/// the emitter. So the grip sat away from the convergence the eye is looking
/// at, and moving the clip read as sending it somewhere unrelated.
@MainActor
@Suite("Clip origin")
struct ClipOriginTests {
    private func shellWithClip() -> (EditorShellModel, EffectNode.ID) {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)
        shell.selectedNodeID = node?.id
        return (shell, node?.id ?? "")
    }

    @Test("nothing selected reports no origin")
    func noSelection() {
        let shell = EditorShellModel()
        #expect(shell.clipOrigin == nil)
    }

    @Test("the origin is the clip's own position")
    func originIsThePosition() throws {
        let (shell, id) = shellWithClip()
        shell.setTransformValue(200, for: .x, on: id)
        shell.setTransformValue(120, for: .y, on: id)

        let origin = try #require(shell.clipOrigin)
        #expect(origin.x == 200)
        #expect(origin.y == 120)
    }

    /// Moving the clip has to move the grip by the same amount. The box centre
    /// does not: a radial spray reaching the edges of the stage keeps most of
    /// its extent wherever the emitter goes.
    @Test("the origin follows the clip")
    func originFollowsTheMove() throws {
        let (shell, id) = shellWithClip()
        shell.setTransformValue(320, for: .x, on: id)
        let before = try #require(shell.clipOrigin).x

        shell.setTransformValue(200, for: .x, on: id)
        let after = try #require(shell.clipOrigin).x

        #expect(after - before == -120)
    }

    /// The position fields and the grip describe the same thing, so they have
    /// to agree — a grip that sits somewhere the inspector does not name is a
    /// grip nobody can predict.
    @Test("the origin agrees with the inspector's position fields")
    func originMatchesTheInspector() throws {
        let (shell, id) = shellWithClip()
        shell.setTransformValue(275, for: .x, on: id)
        shell.setTransformValue(95, for: .y, on: id)

        let node = try #require(shell.effects[id])
        let origin = try #require(shell.clipOrigin)

        #expect(origin.x == node.transform[value: .x])
        #expect(origin.y == node.transform[value: .y])
    }
}
