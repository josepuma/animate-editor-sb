import CoreGraphics
import Testing
@testable import PlaybackFeature

/// How the selection frame is held to the stage.
///
/// The frame is an upright box turned afterwards about its centre. Clamping
/// that box to the stage only makes sense while it is upright: a turned
/// sprite's upright box can reach past the stage edge while the sprite itself
/// does not, and clamping it shortened the frame and slid its centre —
/// reported as a frame off a stretched, rotated shape by about twelve points.
@Suite("Selection frame hold")
struct SelectionFrameHoldTests {
    private let view = CGSize(width: 800, height: 600)

    @Test("an upright box is held inside the stage")
    func uprightIsClamped() throws {
        let held = try #require(SelectionBox.held(
            CGRect(x: -50, y: 100, width: 300, height: 700), rotation: 0, in: view,
        ))
        #expect(held.minX == 6 && held.maxY == 594)
    }

    @Test("a turned box keeps its size and centre")
    func turnedIsNotClamped() throws {
        let raw = CGRect(x: 200, y: -40, width: 300, height: 700)
        let held = try #require(SelectionBox.held(raw, rotation: -1.88, in: view))
        #expect(held == raw)
    }

    @Test("a box too small to draw is not drawn")
    func tinyIsDropped() {
        #expect(SelectionBox.held(CGRect(x: 10, y: 10, width: 4, height: 4), rotation: 0, in: view) == nil)
        #expect(SelectionBox.held(CGRect(x: 10, y: 10, width: 4, height: 4), rotation: 0.5, in: view) == nil)
    }
}
