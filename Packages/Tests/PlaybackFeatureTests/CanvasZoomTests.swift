import CoreGraphics
import Testing
@testable import PlaybackFeature

/// The zoom commands the canvas controls and shortcuts call.
@MainActor
@Suite("Canvas zoom")
struct CanvasZoomTests {
    private func model() -> PlaybackModel {
        let model = PlaybackModel()
        model.canvasContainerSize = CGSize(width: 1000, height: 600)
        return model
    }

    /// A preset picked from the menu zooms about the middle of the view —
    /// there is no pointer to keep still.
    @Test("a preset zooms about the middle of the view")
    func presetAboutMiddle() {
        let model = model()
        let size = model.canvasContainerSize
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let before = model.canvasViewport.layout(container: size, stage: model.canvasStageSize)
            .canvasPoint(atView: middle)

        model.setCanvasZoom(0.5)

        #expect(model.canvasViewport.zoom == 0.5)
        let after = model.canvasViewport.layout(container: size, stage: model.canvasStageSize)
            .canvasPoint(atView: middle)
        #expect(abs(before.x - after.x) < 1e-6)
        #expect(abs(before.y - after.y) < 1e-6)
    }

    /// ⌘= and ⌘− walk the same list the menu shows, so a keyboard zoom always
    /// lands on a number the menu can name.
    @Test("stepping walks the presets")
    func stepsThroughPresets() {
        let model = model()
        model.stepCanvasZoom(in: true)
        #expect(model.canvasViewport.zoom == 1.5)
        model.stepCanvasZoom(in: false)
        model.stepCanvasZoom(in: false)
        #expect(model.canvasViewport.zoom == 0.75)
    }

    @Test("stepping stops at the ends")
    func stepStopsAtEnds() {
        let model = model()
        for _ in 0..<20 { model.stepCanvasZoom(in: false) }
        #expect(model.canvasViewport.zoom == CanvasViewport.presets.first)
        for _ in 0..<20 { model.stepCanvasZoom(in: true) }
        #expect(model.canvasViewport.zoom == CanvasViewport.presets.last)
    }

    /// Between presets — after a pinch — a step goes to the next one along,
    /// not back to the one it passed.
    @Test("stepping from between presets goes to the next one along")
    func stepFromBetween() {
        let model = model()
        model.setCanvasZoom(1.2)
        model.stepCanvasZoom(in: true)
        #expect(model.canvasViewport.zoom == 1.5)
        model.setCanvasZoom(1.2)
        model.stepCanvasZoom(in: false)
        #expect(model.canvasViewport.zoom == 1)
    }

    @Test("fit returns to the fitted view")
    func fitResets() {
        let model = model()
        model.setCanvasZoom(2)
        model.panCanvas(by: CGSize(width: 50, height: 0))
        model.fitCanvas()
        #expect(model.canvasViewport.isFitted)
    }

    /// Another project is another picture: opening it fitted, not wherever
    /// the last one was being looked at.
    @Test("a new storyboard opens fitted")
    func loadFits() {
        let model = model()
        model.setCanvasZoom(2)
        model.contentLoaded(name: "x", sprites: [], duration: 0, audioURL: nil)
        #expect(model.canvasViewport.isFitted)
    }
}
