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
        cached("filter:" + descriptor.type, background: filterBackground, focus: filterFocus) {
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
            // Its filters too: a pulse ring without its Audio Drive is a ring
            // standing still, and its preview would say so.
            node.filters = preset.filterNodes(using: .standard) { "preview-f\($0)" }
            // The demo beat rather than the stand-in: a preview has no song,
            // and a preset fired by kicks would never fire over smooth sines.
            return EffectEvaluator(audio: AudioSpectrum.demoBeat).evaluate(node)
        }
    }

    // ─── Rendering ───────────────────────────────────────────────────────────

    private static let previewDuration: Double = 3000

    /// What a filter is shown acting on.
    ///
    /// Chosen to give every filter something to act on, because a filter is
    /// only visible against what it changes. The first subject was sixty soft
    /// dots, still and centred — together a blur — and almost every card looked
    /// the same: a glow on a glow, a blur of a blur, a mirror of something
    /// symmetric, an echo of something that barely moved. Each property here
    /// answers one of those:
    ///
    /// - **Hard edges** (flat arrows, not soft dots): Blur, Glow and Chromatic
    ///   all work on edges, and a soft particle has none.
    /// - **Movement** (a stream heading right): an echo shows where something
    ///   *was*, and a still subject stacks its copies on itself.
    /// - **Direction** (pointing along their path, off to one side of centre):
    ///   a mirror or a radial repeat of something symmetric is itself.
    ///
    /// Shared by every filter, so the cards still compare like for like.
    private static var subject: EffectNode {
        var values = EmitterEffect.descriptor.defaultValues
        values[EmitterEffect.Param.count] = .integer(6)
        values[EmitterEffect.Param.sprite] = .text(BuiltInSprite.arrow)
        values[EmitterEffect.Param.shape] = .choice(EmitterEffect.Shape.point.rawValue)
        // Rightwards, a little fanned: 0 is right in Direction's convention.
        values[EmitterEffect.Param.direction] = .number(0)
        values[EmitterEffect.Param.spread] = .number(30)
        values[EmitterEffect.Param.velocity] = .number(110)
        values[EmitterEffect.Param.life] = .number(2200)
        values[EmitterEffect.Param.alignToMotion] = .toggle(true)
        // The arrow is drawn at 512: about 80 stage units across. Half that
        // was tried, and Blur and LED all but erased it — a blur of fixed
        // radius swallows a small shape, and a dot matrix has too few cells
        // across it to draw one.
        values[EmitterEffect.Param.scaleStart] = .number(0.16)
        values[EmitterEffect.Param.scaleEnd] = .number(0.16)
        // Painted, not lit: additive arrows would burn white where they meet
        // and lose the edges this subject is for.
        values[EmitterEffect.Param.additive] = .toggle(false)
        values[EmitterEffect.Param.color] = .color(EffectColor(r: 200, g: 220, b: 255))
        values[EmitterEffect.Param.colorEnd] = .color(EffectColor(r: 200, g: 220, b: 255))

        return EffectNode(
            id: "subject",
            type: EmitterEffect.descriptor.type,
            name: "Subject",
            startTime: 0,
            duration: previewDuration,
            seed: 3,
            values: values,
        )
    }

    /// Dark grey behind a filter's preview, not black.
    ///
    /// A shadow is a dark copy, and on black it is invisible — Shadow's card
    /// showed the subject and nothing else. Only filters get it: a preset's
    /// preview is a picture of the stage, and the stage is black.
    private static let filterBackground = MTLClearColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1)

    /// Where a filter's preview looks, and how close.
    ///
    /// The whole stage at 240 pixels puts a default 12-unit glow at three
    /// pixels — every filter's own size is lost before it can be seen, and
    /// exaggerating the values instead would make the card lie about what
    /// adding the filter gives. So the preview moves in on the subject, the way
    /// zooming the canvas does: the arrows' path, about a third of the stage.
    private static let filterFocus = Focus(x: 400, y: 240, zoom: 2.5)

    /// A point on the stage and a magnification, for previews that look closer
    /// than the whole frame.
    struct Focus {
        let x: Double
        let y: Double
        let zoom: Double
    }

    private static func cached(
        _ key: String,
        duration: Double = previewDuration,
        background: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
        focus: Focus? = nil,
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
        let made = render(sprites(), duration: duration, background: background, focus: focus)
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
    private static func render(
        _ sprites: [StoryboardSprite],
        duration: Double,
        background: MTLClearColor,
        focus: Focus?,
    ) -> [CGImage] {
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
                // The app's whole chain — derived, text, built-in — the one the
                // canvas and the export resolve with. A preview has no beatmap,
                // so the mapper's own files are the one link it lacks.
                //
                // It used to ask only the built-ins and the text glyphs. Text
                // had already been learned the hard way (every text preview a
                // white box); the derived images were not: Blur, LED, Glow and
                // Shadow swap a sprite's image for a derived one
                // (`__derived__/…`), which resolved to nothing, so those four
                // cards showed specks or the bare subject — never the filter.
                StoryboardExport.appImageData(for: path, beatmapImage: { _ in nil }).map { .data($0) }
            }
        } catch {
            return []
        }

        // Rendered larger and cropped when looking closer: the same pixels a
        // zoomed camera would give, without the renderer needing one.
        let scale = focus?.zoom ?? 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: TextureAtlas.pixelFormat,
            width: Int((Double(width) * scale).rounded()),
            height: Int((Double(height) * scale).rounded()),
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
            guard renderer.render(at: at, into: texture, background: background),
                  let frame = image(from: texture)
            else { return nil }
            guard let focus else { return frame }
            return cropped(frame, to: focus)
        }
    }

    /// The part of a frame around `focus`, redrawn at preview size.
    ///
    /// Redrawn into its own bitmap rather than kept as a `cropping(to:)`
    /// result, which would hold the whole enlarged frame alive per image.
    private static func cropped(_ frame: CGImage, to focus: Focus) -> CGImage? {
        let frameWidth = Double(frame.width)
        let frameHeight = Double(frame.height)
        // Stage to pixels: the frame spans the widescreen stage, which starts
        // `xOffset` to the left of storyboard x = 0.
        let centreX = (focus.x + Double(OsuCanvas.xOffset)) / Double(OsuCanvas.width) * frameWidth
        let centreY = focus.y / Double(OsuCanvas.height) * frameHeight
        let cropWidth = frameWidth / focus.zoom
        let cropHeight = frameHeight / focus.zoom
        let crop = CGRect(
            x: min(max(centreX - cropWidth / 2, 0), frameWidth - cropWidth),
            y: min(max(centreY - cropHeight / 2, 0), frameHeight - cropHeight),
            width: cropWidth,
            height: cropHeight,
        ).integral

        guard let part = frame.cropping(to: crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
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
