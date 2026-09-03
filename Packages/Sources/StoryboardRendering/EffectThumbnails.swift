import CoreGraphics
import Foundation
import Metal
import MetalKit
import StoryboardCore

/// Small still images of what each effect and filter does.
///
/// A library of twenty entries with nothing but names is a library you have to
/// place things out of to find out what they are. A picture answers "what is
/// this?" in the time it takes to look, which is the question someone browsing
/// actually has.
///
/// **Stills rather than animation**, and deliberately: the movement is the
/// smaller half of what an effect *is*, and it is on screen the moment the clip
/// is placed. A frame can be rendered once and kept, so the panel opens at the
/// same speed whether or not it has pictures in it — an animated preview that
/// stutters while scrolling teaches less than a still that does not.
@MainActor
public enum EffectThumbnails {
    /// Small enough to sit in a tooltip, large enough to read a shape in.
    ///
    /// Shaped like the stage, not square. Sprites are positioned in stage
    /// coordinates — 854 across — so a square target puts everything past the
    /// first 160 units off the edge: the render came back as the clear colour
    /// and every preview was an empty rectangle.
    public static let width = 240
    public static var height: Int {
        Int((Double(width) * Double(OsuCanvas.height) / Double(OsuCanvas.width)).rounded())
    }

    /// How many frames a preview holds.
    ///
    /// Enough to read a movement, few enough to render while a tooltip is
    /// opening: twelve over the clip is one every 250ms on a three-second
    /// effect, which is where a letter arriving stops being a jump and starts
    /// being an arrival.
    public static let frameCount = 12

    private static var cache: [String: [CGImage]] = [:]

    /// The picture for one effect, rendered on first ask and kept after.
    public static func frames(for descriptor: EffectDescriptor) -> [CGImage] {
        cached("effect:" + descriptor.type) {
            let node = EffectNode(
                id: "preview",
                type: descriptor.type,
                name: descriptor.name,
                startTime: 0,
                duration: previewDuration,
                seed: 7,
                values: descriptor.defaultValues,
            )
            // No transform.
            //
            // An emitter already emits around the stage centre, and setting the
            // transform to that centre applies the offset a second time —
            // `GroupTransform` carries every sprite relative to the clip, so
            // the whole field was pushed off the edge and the render came back
            // as the clear colour. Compound presets never had one set, which is
            // why Portal and Fire Ring were the only previews that worked.
            return EffectEvaluator().evaluate(node)
        }
    }

    /// The picture for one filter, over a fixed subject.
    ///
    /// A filter cannot be shown on its own — it needs something to act on — so
    /// every one is shown over the **same** subject. That is what makes the
    /// pictures comparable: Glow beside Blur over identical input is the
    /// comparison someone is making when they choose between them.
    public static func frames(for descriptor: FilterDescriptor) -> [CGImage] {
        cached("filter:" + descriptor.type) {
            var node = subject
            node.filters = [FilterNode(
                id: "preview-filter",
                type: descriptor.type,
                values: descriptor.defaultValues,
            )]
            return EffectEvaluator().evaluate(node)
        }
    }

    /// The picture for one preset.
    public static func frames(for preset: EffectPreset) -> [CGImage] {
        cached("preset:" + preset.id, duration: preset.duration) {
            var node = EffectNode(
                id: "preview",
                type: preset.effectType,
                name: preset.name,
                startTime: 0,
                duration: preset.duration,
                seed: 7,
                values: preset.values,
            )
            node.layers = preset.layers.enumerated().map { index, layer in
                EffectNode(
                    id: "preview/L\(index)",
                    type: layer.effectType,
                    name: layer.name,
                    startTime: 0,
                    duration: preset.duration,
                    seed: EffectNode.layerSeed(from: 7, index: index),
                    values: layer.values,
                )
            }
            return EffectEvaluator().evaluate(node)
        }
    }

    // ─── Rendering ───────────────────────────────────────────────────────────

    private static let previewDuration: Double = 3000

    /// What a filter is shown acting on.
    ///
    /// A modest emitter rather than one sprite: a glow over a single dot says
    /// almost nothing, while the same glow over a scattering of them shows how
    /// it accumulates — which is the part worth seeing before committing to it.
    private static var subject: EffectNode {
        var values = EmitterEffect.descriptor.defaultValues
        values[EmitterEffect.Param.count] = .integer(60)
        values[EmitterEffect.Param.width] = .number(220)
        values[EmitterEffect.Param.height] = .number(140)
        values[EmitterEffect.Param.velocity] = .number(20)
        values[EmitterEffect.Param.life] = .number(2500)
        values[EmitterEffect.Param.scaleStart] = .number(0.5)
        values[EmitterEffect.Param.scaleEnd] = .number(0.4)
        values[EmitterEffect.Param.color] = .color(EffectColor(r: 200, g: 220, b: 255))
        values[EmitterEffect.Param.colorEnd] = .color(EffectColor(r: 120, g: 160, b: 255))

        let node = EffectNode(
            id: "subject",
            type: EmitterEffect.descriptor.type,
            name: "Subject",
            startTime: 0,
            duration: previewDuration,
            seed: 3,
            values: values,
        )
        return node
    }

    private static func cached(
        _ key: String,
        duration: Double = previewDuration,
        sprites: () -> [StoryboardSprite],
    ) -> [CGImage] {
        if let existing = cache[key] { return existing }

        // Before the effect is evaluated, not before it is drawn.
        //
        // A text effect lays itself out at evaluation, asking `TextMetrics` how
        // wide each glyph is — and with no measurer installed it falls back to
        // rough widths and its glyphs come out as plain boxes. Every text
        // preview was a white rectangle for exactly this reason: the app
        // installs the measurer at launch, and a thumbnail asked for before
        // that had none.
        TextTextures.install()
        let made = render(sprites(), duration: duration)
        cache[key] = made
        return made
    }

    /// Draws sprites into an image, using the same renderer the canvas does.
    ///
    /// A third of the way in rather than halfway.
    ///
    /// Halfway is where a continuous emitter is fullest, and it is also where
    /// most entrances have already finished — two text presets that arrive very
    /// differently both showed the same settled word, which tells a browser
    /// nothing about the difference between them. A third in, an emitter is
    /// already dense and an entrance is still visibly happening.
    private static func render(_ sprites: [StoryboardSprite], duration: Double) -> [CGImage] {
        guard !sprites.isEmpty,
              let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? MetalStoryboardRenderer(
                  device: device,
                  pixelFormat: TextureAtlas.pixelFormat,
              )
        else { return [] }

        let prepared = StoryboardResolver.prepare(sprites)
        do {
            try renderer.setSprites(prepared) { path in
                // Text glyphs as well as the built-in shapes.
                //
                // A text effect names its glyphs `__text__/<hash>.png`, which
                // `BuiltInTextures` knows nothing about — asked only for those,
                // the renderer found no image and drew bare quads. Every text
                // preview was a white box, and two presets that animate very
                // differently produced byte-identical pictures, because a box
                // is a box.
                let data = BuiltInTextures.data(for: path) ?? TextTextures.data(for: path)
                return data.map { .data($0) }
            }
        } catch {
            return []
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: TextureAtlas.pixelFormat,
            width: width,
            height: height,
            mipmapped: false,
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [] }

        // Every frame from the one set-up.
        //
        // Building the atlas and uploading the textures is nearly all the cost
        // here; drawing a frame afterwards is a command buffer. Twelve frames
        // are barely more expensive than one, which is what makes an animated
        // preview affordable at all.
        //
        // Weighted towards the beginning, not spread evenly.
        //
        // What distinguishes one preset from another is its **entrance**, and
        // that happens in the first fraction of the clip: sampled evenly, the
        // first frame lands on an empty stage and the second already shows the
        // finished thing. Squaring the position spends most of the frames where
        // the difference actually is, and still reaches the settled state at
        // the end.
        //
        // Stopping short of the very end, too: a clip's last moments are mostly
        // empty as everything fades out, and a loop that spends a sixth of its
        // time on a blank frame reads as broken.
        return (0 ..< frameCount).compactMap { index in
            let progress = Double(index) / Double(frameCount - 1)
            let at = duration * 0.8 * progress * progress
            guard renderer.render(at: at, into: texture) else { return nil }
            return image(from: texture)
        }
    }

    /// Copies a rendered texture into a `CGImage`.
    ///
    /// The channel order has to be stated, not assumed: the atlas format is
    /// BGRA on this platform and `getBytes` copies bytes without reordering
    /// them, so a picture built as RGBA comes out with its reds and blues
    /// swapped — the same trap the video export hit, where fire exported blue.
    private static func image(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4

        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
            )
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }

        let isBGRA = TextureAtlas.pixelFormat == .bgra8Unorm
        let info: CGBitmapInfo = isBGRA
            ? [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]
            : [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent,
        )
    }
}
