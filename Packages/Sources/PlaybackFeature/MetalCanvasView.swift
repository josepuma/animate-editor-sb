import MetalKit
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// An `MTKView` that reports when the pointer is over it.
///
/// SwiftUI's `onHover` never fires for a view wrapping this one: an AppKit view
/// handles its own mouse tracking and does not pass those events up, so the
/// canvas has to report them itself.
final class HoverReportingMTKView: MTKView {
    var onHoverChange: (Bool) -> Void = { _ in }

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        // `.activeInKeyWindow` rather than `.activeAlways`: a background window
        // revealing its controls under a passing pointer is noise.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange(false)
    }
}

/// Hosts the Metal renderer inside SwiftUI and drives it from the display link.
struct MetalCanvasView: NSViewRepresentable {
    let model: PlaybackModel
    let source: any StoryboardSource
    /// Called as the pointer enters and leaves the picture.
    var onHoverChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, source: source)
    }

    func makeNSView(context: Context) -> HoverReportingMTKView {
        let view = HoverReportingMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        // osu! composites a storyboard over black, and anything else tints
        // every partly transparent sprite.
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.onHoverChange = onHoverChange
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_ view: HoverReportingMTKView, context _: Context) {
        view.onHoverChange = onHoverChange
    }

    /// Owns the renderer and advances the clock once per frame.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let model: PlaybackModel
        private let source: any StoryboardSource
        private var renderer: MetalStoryboardRenderer?
        private var lastFrameTimestamp: CFTimeInterval?
        private var smoothedFPS: Double = 60

        init(model: PlaybackModel, source: any StoryboardSource) {
            self.model = model
            self.source = source
        }

        func configure(view: MTKView) {
            guard let device = view.device else {
                model.contentFailed("No Metal device available.")
                return
            }

            do {
                let renderer = try MetalStoryboardRenderer(
                    device: device,
                    pixelFormat: view.colorPixelFormat,
                )
                let sprites = try source.loadSprites()
                try renderer.setSprites(sprites) { [source] path in
                    source.imageData(for: path).map { .data($0) }
                }

                self.renderer = renderer
                model.contentLoaded(
                    name: source.displayName,
                    sprites: sprites,
                    duration: StoryboardResolver.duration(of: sprites),
                    audioURL: source.audioURL,
                    timing: source.timing,
                    missingImagePaths: source.missingImagePaths,
                )
            } catch {
                model.contentFailed("\(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            let now = CACurrentMediaTime()
            if let last = lastFrameTimestamp {
                let delta = now - last
                if delta > 0 {
                    smoothedFPS = smoothedFPS * 0.9 + (1 / delta) * 0.1
                }
                model.advance(by: delta * 1000)
            }
            lastFrameTimestamp = now

            guard let renderer else { return }
            renderer.draw(at: model.currentTime, in: view)
            model.frameRendered(
                drawnCount: renderer.lastDrawnCount,
                framesPerSecond: smoothedFPS,
            )
        }
    }
}
