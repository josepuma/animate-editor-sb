import CoreGraphics
import Testing

@testable import PlaybackFeature

/// The view onto the canvas: how much of it, and from where.
///
/// Zoomed out, what is off the stage is visible and reachable — a sprite
/// parked outside the frame, or a selection frame bigger than the stage. None
/// of it reaches the storyboard; it is how the canvas is looked at.
@Suite("Canvas viewport")
struct CanvasViewportTests {
    private let stage = CGSize(width: 854, height: 480)
    private let container = CGSize(width: 1000, height: 600)

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-6 }

    /// At 100% nothing changes from before zoom existed: the stage fits the
    /// space it is given, centred.
    @Test("at 100% the stage fits the container, centred")
    func fitsAtOne() {
        let layout = CanvasViewport().layout(container: container, stage: stage)
        let fit = min(1000 / 854.0, 600 / 480.0)

        #expect(close(layout.stageRect.width, 854 * fit))
        #expect(close(layout.stageRect.height, 480 * fit))
        #expect(close(layout.stageRect.midX, 500))
        #expect(close(layout.stageRect.midY, 300))
    }

    @Test("at 100% the visible canvas spans the stage's width")
    func visibleAtOne() {
        let layout = CanvasViewport().layout(container: container, stage: stage)
        #expect(close(layout.visible.minX, 0))
        #expect(close(layout.visible.maxX, 854))
    }

    /// Zoomed out to half, the stage takes half the room and as much again of
    /// the canvas shows around it.
    @Test("at 50% the stage halves and twice as much canvas shows")
    func halfZoom() {
        let layout = CanvasViewport(zoom: 0.5).layout(container: container, stage: stage)
        let full = CanvasViewport().layout(container: container, stage: stage)

        #expect(close(layout.stageRect.width, full.stageRect.width / 2))
        #expect(close(layout.visible.width, full.visible.width * 2))
        #expect(close(layout.visible.midX, 427))
    }

    @Test("a point on the view and on the canvas convert both ways")
    func roundTrip() {
        let layout = CanvasViewport(zoom: 1.7, centre: CGPoint(x: 300, y: 200))
            .layout(container: container, stage: stage)
        let view = CGPoint(x: 123, y: 456)
        let back = layout.viewPoint(ofCanvas: layout.canvasPoint(atView: view))
        #expect(close(back.x, view.x))
        #expect(close(back.y, view.y))
    }

    /// The stage's corner is where the stage rect's corner is drawn.
    @Test("the stage corner sits at the stage rect's corner")
    func cornerAgrees() {
        let layout = CanvasViewport(zoom: 2, centre: CGPoint(x: 200, y: 100))
            .layout(container: container, stage: stage)
        let corner = layout.viewPoint(ofCanvas: .zero)
        #expect(close(corner.x, layout.stageRect.minX))
        #expect(close(corner.y, layout.stageRect.minY))
    }

    /// Zooming toward the centre of the view when the pointer is over a
    /// sprite in the corner sends that sprite off screen just as it is
    /// being looked at.
    @Test("zooming keeps the point under the pointer still")
    func zoomAboutPointer() {
        var viewport = CanvasViewport()
        let pointer = CGPoint(x: 820, y: 140)
        let before = viewport.layout(container: container, stage: stage).canvasPoint(atView: pointer)

        viewport.zoom(to: 2.5, keeping: pointer, container: container, stage: stage)

        let after = viewport.layout(container: container, stage: stage).canvasPoint(atView: pointer)
        #expect(close(before.x, after.x))
        #expect(close(before.y, after.y))
    }

    @Test("zoom stays within its range")
    func zoomClamps() {
        var viewport = CanvasViewport()
        viewport.zoom(to: 100, keeping: .zero, container: container, stage: stage)
        #expect(viewport.zoom == CanvasViewport.maximumZoom)
        viewport.zoom(to: 0.01, keeping: .zero, container: container, stage: stage)
        #expect(viewport.zoom == CanvasViewport.minimumZoom)
    }

    /// Panned without limit the stage can be lost entirely, and finding it
    /// again is a chore. Its centre of view stays somewhere on it.
    @Test("panning stops with the view centred on the stage's edge")
    func panClamps() {
        var viewport = CanvasViewport(zoom: 2)
        viewport.pan(by: CGSize(width: 100_000, height: -100_000), container: container, stage: stage)
        let centre = viewport.layout(container: container, stage: stage).visible
        #expect(close(centre.midX, 0))
        #expect(close(centre.midY, 480))
    }

    @Test("panning moves the picture with the hand")
    func panFollowsHand() {
        var viewport = CanvasViewport(zoom: 2)
        let before = viewport.layout(container: container, stage: stage).stageRect
        viewport.pan(by: CGSize(width: 30, height: -20), container: container, stage: stage)
        let after = viewport.layout(container: container, stage: stage).stageRect
        #expect(close(after.minX - before.minX, 30))
        #expect(close(after.minY - before.minY, -20))
    }

    @Test("fit goes back to 100%, centred")
    func fitResets() {
        var viewport = CanvasViewport(zoom: 3, centre: CGPoint(x: 10, y: 10))
        viewport.fit()
        #expect(viewport == CanvasViewport())
    }

    @Test("the presets include 100%")
    func presetsIncludeFit() {
        #expect(CanvasViewport.presets.contains(1))
        #expect(CanvasViewport.presets == CanvasViewport.presets.sorted())
    }
}
