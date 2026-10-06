import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// Turning a clip from the canvas, by the knob above its frame.
@MainActor
@Suite("Canvas rotate")
struct CanvasRotateTests {
    @Test("a turn on the canvas adds to the clip's rotation")
    func turnAddsToRotation() throws {
        let shell = EditorShellModel()
        let node = shell.addEffect(ShapeEffect.descriptor, at: 0, duration: 4000)
        shell.setTransformValue(10, for: .rotation, on: node.id)

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 1, scaleY: 1, rotation: 35, isFinished: true, at: 1000)

        let turned = try #require(shell.effects[node.id])
        #expect(turned.transform[value: .rotation] == 45)
        #expect(turned.transform[value: .x] == node.transform[value: .x], "a turn moved the clip")
    }

    /// The same rule the inspector follows: a property that animates gets a
    /// key at the playhead, not a new resting value.
    @Test("an animated rotation gets a key at the playhead")
    func animatedRotationGetsAKey() throws {
        let shell = EditorShellModel()
        let node = shell.addEffect(ShapeEffect.descriptor, at: 0, duration: 4000)
        shell.selectedNodeID = node.id
        // The stopwatch's first click: a key holding the current value.
        shell.beginAnimating(.rotation, on: node.id, at: 0)

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 1, scaleY: 1, rotation: 30, isFinished: true, at: 2000)

        let turned = try #require(shell.effects[node.id])
        #expect(turned.transform.value(.rotation, at: 2000) == 30)
        #expect(turned.transform[value: .rotation] == 0, "the resting value moved instead of a key")
    }
}
