import CoreGraphics
import Foundation
import Metal
import StoryboardCore

/// One still per timeline clip, of what that clip actually draws.
///
/// The library previews (`EffectThumbnails`) evaluate a stand-in node; these
/// never evaluate anything. A clip's sprites already exist — the editor's
/// evaluation pass produced them for the canvas — so a still is those sprites
/// drawn once, at one instant, and cropped to where they are.
///
/// **Cropped to the clip, not the stage.** Most clips occupy a small part of
/// an 854-wide stage, and a 36pt slot showing the whole stage turns a text line
/// or a burst into an unreadable dot. What a block on a timeline is asked is
/// "which one is this?", and the clip's own pixels answer it.
@MainActor
public enum ClipStills {
    /// Stage pixels the frame is drawn at before cropping.
    ///
    /// Generous on purpose: the crop is often a tenth of the stage, and a
    /// crop rendered small is upscaled into mush. The cost is one texture
    /// reused for the whole batch and one read-back per clip.
    static let renderWidth = 1280

    static var renderHeight: Int {
        Int((Double(renderWidth) * Double(OsuCanvas.height) / Double(OsuCanvas.width)).rounded())
    }

    /// The height of the image kept per clip, in pixels.
    ///
    /// The slot is about 24pt tall, so twice that on a Retina display is
    /// already sharp — and every clip in the project keeps one of these alive.
    /// Redrawn into its own small bitmap rather than handed back as a
    /// `cropping(to:)` of the frame: a cropped `CGImage` shares the *whole*
    /// frame's backing store, which would be 3.6MB held per clip.
    static let outputHeight = 96

    /// How much air is left around the clip's own box, as a fraction of it.
    ///
    /// Without it the outermost pixels sit flush against the slot's rounded
    /// corner and get clipped by it.
    static let padding = 0.1

    /// Sets up one renderer for a batch of clips and returns a function that
    /// draws each of them.
    ///
    /// The set-up — sorting, building the atlas, uploading every page — is
    /// nearly all the cost, so it is paid once for the batch rather than once
    /// per clip; drawing a clip afterwards is a command buffer and a read-back.
    /// The renderer lives as long as the returned function does, which is as
    /// long as the batch.
    ///
    /// - Parameters:
    ///   - sprites: every sprite of every clip in the batch, already prepared.
    ///   - aspect: width over height of the slot the still goes in.
    ///   - beatmapImage: a sprite path's bytes from the beatmap folder. Asked
    ///     last, after the app's own images, through the same chain the canvas
    ///     and the export resolve with — a clip can draw the mapper's `bg.jpg`
    ///     or a blurred copy of it, and a resolver that only knew the built-ins
    ///     would draw those as flat quads.
    public static func renderer(
        for sprites: [PreparedSprite],
        aspect: Double,
        beatmapImage: (String) -> Data?,
    ) -> ((_ clipID: String, _ time: Double) -> CGImage?)? {
        guard !sprites.isEmpty,
              let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? MetalStoryboardRenderer(
                  device: device,
                  pixelFormat: TextureAtlas.pixelFormat,
              )
        else { return nil }

        do {
            try renderer.setSprites(sprites) { path in
                StoryboardExport.appImageData(for: path, beatmapImage: beatmapImage).map { .data($0) }
            }
        } catch {
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: TextureAtlas.pixelFormat,
            width: renderWidth,
            height: renderHeight,
            mipmapped: false,
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        return { clipID, time in
            // Only this clip, measured as it is drawn: the box comes from the
            // same pass that resolves the sprites, sized from the atlas the
            // renderer actually holds — the selection frame's measurement,
            // origins and all.
            renderer.drawnClipID = clipID
            renderer.measuredClipID = clipID
            guard renderer.render(at: time, into: texture),
                  renderer.lastDrawnCount > 0,
                  let frame = EffectThumbnails.image(from: texture)
            else { return nil }

            let crop = cropRect(around: renderer.measuredBounds, aspect: aspect)
            return still(from: frame, crop: crop)
        }
    }

    /// The part of the stage to keep, in stage units.
    ///
    /// The clip's box, padded, widened or heightened to the slot's shape, and
    /// slid back inside the stage. A box with no area — a clip that measured
    /// nothing, or a single hairline — falls back to the whole stage: a crop
    /// of nothing is a blank image, and the stage at least shows something.
    static func cropRect(around bounds: ClipBounds?, aspect: Double) -> CGRect {
        let stageMinX = -Double(OsuCanvas.xOffset)
        let stageWidth = Double(OsuCanvas.width)
        let stageHeight = Double(OsuCanvas.height)
        let stage = CGRect(x: stageMinX, y: 0, width: stageWidth, height: stageHeight)

        // Clamped to the stage first: an emitter's box measures every particle
        // in flight, and a burst can report thousands of units of spray
        // reaching far past the frame. What is off the stage is not drawn.
        guard let bounds else { return stage }
        let visible = CGRect(
            x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height,
        ).intersection(stage)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return stage }

        var width = visible.width * (1 + 2 * padding)
        var height = visible.height * (1 + 2 * padding)
        if width / height < aspect {
            width = height * aspect
        } else {
            height = width / aspect
        }
        // Never larger than the stage: past it there is only the clear colour.
        width = min(width, stageWidth)
        height = min(height, stageHeight)

        var x = visible.midX - width / 2
        var y = visible.midY - height / 2
        x = min(max(x, stage.minX), stage.maxX - width)
        y = min(max(y, stage.minY), stage.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The crop, redrawn small into a bitmap of its own.
    private static func still(from frame: CGImage, crop: CGRect) -> CGImage? {
        // Stage units to texture pixels. Storyboard x starts 107 to the left
        // of the wide stage, which is what the renderer adds before drawing.
        let pixelsPerUnit = Double(frame.width) / Double(OsuCanvas.width)
        let pixelRect = CGRect(
            x: (crop.minX + Double(OsuCanvas.xOffset)) * pixelsPerUnit,
            y: crop.minY * pixelsPerUnit,
            width: crop.width * pixelsPerUnit,
            height: crop.height * pixelsPerUnit,
        ).integral
        guard let cropped = frame.cropping(to: pixelRect) else { return nil }

        // The crop's own shape, not the slot's: when the clip fills the stage
        // the crop cannot reach the slot's aspect, and the view fills the rest.
        let height = outputHeight
        let width = max(1, Int((Double(height) * crop.width / crop.height).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
