import CoreGraphics
import Testing
@testable import PlaybackFeature

/// Zoomed out, the canvas shows more than the stage, and the frame is held to
/// what is visible rather than to the stage — the reason to zoom out is to
/// see a frame larger than the stage whole, corners and handles included.
@Suite("Selection frame in the visible area")
struct SelectionFrameAreaTests {
    /// The stage view is 800×450; zoomed out, the container shows 300 points
    /// more on each side and 200 above and below.
    private let area = CGRect(x: -300, y: -200, width: 1400, height: 850)

    @Test("a frame past the stage edge is not cut at the stage")
    func notCutAtStage() throws {
        let raw = CGRect(x: -250, y: -100, width: 600, height: 300)
        let held = try #require(SelectionBox.held(raw, rotation: 0, in: area))
        #expect(held == raw)
    }

    @Test("a frame past the visible area is held inside it")
    func heldToVisible() throws {
        let raw = CGRect(x: -900, y: -100, width: 1200, height: 300)
        let held = try #require(SelectionBox.held(raw, rotation: 0, in: area))
        #expect(held.minX == area.minX + SelectionBox.edgeInset)
        #expect(held.maxX == raw.maxX)
    }

    /// At the fitted view the visible area is the stage, and nothing changes.
    @Test("with the stage as the area, it holds as before")
    func stageAreaUnchanged() {
        let size = CGSize(width: 800, height: 450)
        let raw = CGRect(x: -50, y: 20, width: 300, height: 100)
        #expect(
            SelectionBox.held(raw, rotation: 0, in: CGRect(origin: .zero, size: size))
                == SelectionBox.held(raw, rotation: 0, in: size),
        )
    }

    @Test("a clip off the stage but in view is still framed at rest")
    func offStageInViewIsFramed() {
        let raw = CGRect(x: -200, y: 50, width: 4, height: 100)
        #expect(SelectionBox.shown(raw, rotation: 0, in: area, isDragging: false) != nil)
    }
}
