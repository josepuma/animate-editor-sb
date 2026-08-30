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
        // Plain `bgra8Unorm`, not the `_srgb` variant.
        //
        // osu! composites its storyboards in gamma space — sprite colours are
        // blended as the bytes stand, without a conversion to linear light and
        // back. Declaring sRGB here makes the GPU do that conversion, which is
        // more correct in the abstract and wrong for matching what the artwork
        // was drawn against: overlaps darken and edges pick up a fringe.
        view.colorPixelFormat = .bgra8Unorm
        // osu! composites a storyboard over black, and anything else tints
        // every partly transparent sprite.
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_: MTKView, context: Context) {
        context.coordinator.setWidescreen(model.isWidescreen)
    }

    /// Owns the renderer and advances the clock once per frame.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let model: PlaybackModel
        private let source: any StoryboardSource
        private var renderer: MetalStoryboardRenderer?
        private var lastFrameTimestamp: CFTimeInterval?
        private var smoothedFPS: Double = 60
        /// The sprite revision already on the GPU.
        private var uploadedRevision: Int?

        init(model: PlaybackModel, source: any StoryboardSource) {
            self.model = model
            self.source = source
        }

        /// Loads the storyboard, keeping the window responsive while it does.
        ///
        /// Parsing a `.osb` and resolving its commands is seconds of work on a
        /// real beatmap, so it runs off the main thread; only the texture
        /// upload has to stay, because the renderer owns GPU resources and is
        /// main-actor bound.
        func configure(view: MTKView) {
            guard let device = view.device else {
                model.contentFailed("No Metal device available.")
                return
            }

            model.contentLoading()

            let source = source
            Task { [weak self] in
                do {
                    let sprites = try await Task.detached(priority: .userInitiated) {
                        try source.loadSprites()
                    }.value

                    guard let self else { return }

                    let renderer = try MetalStoryboardRenderer(
                        device: device,
                        pixelFormat: view.colorPixelFormat,
                    )
                    try renderer.setSprites(sprites) { path in
                        Self.imageData(for: path, source: source).map { .data($0) }
                    }

                    renderer.isWidescreen = model.isWidescreen
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
                    self?.model.contentFailed("\(error)")
                }
            }
        }

        /// Resolves a sprite path to image data, wherever it comes from.
        ///
        /// Three places, in order. A *derived* path is made on demand — a glow's
        /// blurred copy of some other sprite — and it needs the resolver itself
        /// to find its source, which is why this is one function rather than a
        /// chain of `??`. A *built-in* is an image the app ships, because an
        /// effect has to draw something before any file has been chosen. Failing
        /// both, the beatmap's own folder.
        static func imageData(for path: String, source: any StoryboardSource) -> Data? {
            if DerivedSprite.isDerived(path) {
                return DerivedTextures.data(for: path) { original in
                    imageData(for: original, source: source)
                }
            }
            return BuiltInTextures.data(for: path) ?? source.imageData(for: path)
        }

        func setWidescreen(_ isWidescreen: Bool) {
            renderer?.isWidescreen = isWidescreen
        }

        /// Uploads the model's sprites when they differ from what the GPU holds.
        ///
        /// Guarded by a revision rather than by comparing the arrays: a real
        /// beatmap carries thousands of sprites, and this runs on every SwiftUI
        /// update.
        func syncSprites() {
            guard let renderer, uploadedRevision != model.spritesRevision else { return }
            uploadedRevision = model.spritesRevision

            let source = source
            do {
                try renderer.setSprites(model.sprites) { path in
                    Self.imageData(for: path, source: source).map { .data($0) }
                }
            } catch {
                model.contentFailed("\(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            // Checked here rather than from `updateNSView`, which only runs
            // when SwiftUI re-evaluates this view — and it has no reason to,
            // since nothing in the view's own body reads the revision. The
            // display link is already running, and the check is one integer
            // comparison per frame.
            syncSprites()

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
