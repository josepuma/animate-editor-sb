import MetalKit
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// Hosts the Metal renderer inside SwiftUI and drives it from the display link.
struct MetalCanvasView: NSViewRepresentable {
    let model: PlaybackModel
    let source: any StoryboardSource

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, source: source)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        // osu! composites a storyboard over black, and anything else tints
        // every partly transparent sprite.
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

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
