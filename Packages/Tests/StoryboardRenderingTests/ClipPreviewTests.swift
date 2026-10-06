import Testing
import StoryboardCore
@testable import StoryboardRendering

/// The picture of a clip being dragged, before the drag is committed.
///
/// Writing to the document per drag event re-evaluates the clip, so nothing is
/// written until the hand comes up — and until then the canvas showed the clip
/// where it was, with only the frame following the pointer. The preview moves
/// what is drawn instead, at draw time, the way the frame already does.
@Suite("Clip preview")
struct ClipPreviewTests {
    private func state(id: String = "clip/0", x: Double = 400, y: Double = 300) -> SpriteRenderState {
        var state = SpriteRenderState(spriteId: id)
        state.x = x
        state.y = y
        state.scaleX = 0.5
        state.scaleY = 0.25
        return state
    }

    @Test("a move shifts the clip's sprites by the drag")
    func moveShifts() {
        let preview = ClipPreview(clipID: "clip", dx: 30, dy: -20)
        var moved = state()
        preview.apply(to: &moved)
        #expect(moved.x == 430 && moved.y == 280)
        #expect(moved.scaleX == 0.5 && moved.scaleY == 0.25)
    }

    /// About the clip's own position, which is where a committed scale grows
    /// from — so the preview and the release agree.
    @Test("a scale grows the clip about its pivot")
    func scaleAboutPivot() {
        let preview = ClipPreview(clipID: "clip", scaleX: 2, scaleY: 3, pivotX: 300, pivotY: 200)
        var scaled = state()
        preview.apply(to: &scaled)
        #expect(scaled.x == 500 && scaled.y == 500)
        #expect(scaled.scaleX == 1 && scaled.scaleY == 0.75)
    }

    /// A quarter turn clockwise on screen, where y grows downwards: a point to
    /// the right of the pivot ends up below it, and the sprite turns with it.
    @Test("a rotation turns the clip about its pivot")
    func rotationAboutPivot() {
        let preview = ClipPreview(clipID: "clip", rotation: 90, pivotX: 300, pivotY: 300)
        var turned = state(x: 400, y: 300)
        preview.apply(to: &turned)
        #expect(abs(turned.x - 300) < 1e-9 && abs(turned.y - 400) < 1e-9, "got \(turned.x), \(turned.y)")
        #expect(abs(turned.rotation - .pi / 2) < 1e-9)
    }

    @Test("only the dragged clip's sprites move")
    func otherClipsStay() {
        let preview = ClipPreview(clipID: "clip", dx: 30, dy: 0)
        #expect(preview.covers("clip/0"))
        #expect(preview.covers("clip"))
        #expect(!preview.covers("other/0"))
        #expect(!preview.covers("clipper/0"))
    }
}
