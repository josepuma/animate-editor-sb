import Metal
import MetalKit
import StoryboardCore
import StoryboardShaderTypes
import simd

/// osu! storyboard canvas, 16:9.
///
/// Storyboard space: x ∈ [-107, 747], y ∈ [0, 480], centre (320, 240).
/// Canvas space:     x ∈ [0, 854],    y ∈ [0, 480].
public enum OsuCanvas {
    public static let width: Float = 854
    public static let height: Float = 480
    /// Added to storyboard x to reach canvas x.
    public static let xOffset: Float = 107

    /// The 4:3 stage, for beatmaps whose `.osu` has widescreen support off.
    ///
    /// Those storyboards were authored against the narrower frame, so osu!
    /// pillarboxes them rather than stretching. Drawing them across the wide
    /// stage would put every sprite in the wrong place.
    public static let narrowWidth: Float = 640

    /// The stage's own dimensions for a given beatmap.
    public static func size(widescreen: Bool) -> (width: Float, height: Float) {
        (widescreen ? width : narrowWidth, height)
    }

    /// How far storyboard x is shifted to reach canvas x.
    ///
    /// Only the wide stage has room either side of the 640-point playfield; on
    /// the narrow one the two spaces are the same.
    public static func offset(widescreen: Bool) -> Float {
        widescreen ? xOffset : 0
    }
}

/// Draws resolved storyboard sprites with Metal.
///
/// Sprites are batched into one instance buffer and split into two draw calls,
/// one per blend mode. Textures live in a single array texture, so a whole
/// batch samples without rebinding.
/// Driven from `MTKViewDelegate.draw(in:)`, which AppKit calls on the main
/// thread, so the whole renderer is main-actor isolated.
@MainActor
public final class MetalStoryboardRenderer {
    public let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let normalPipeline: MTLRenderPipelineState
    private let additivePipeline: MTLRenderPipelineState
    private let untexturedPipeline: MTLRenderPipelineState
    private let samplerState: MTLSamplerState

    /// Triple buffering: the CPU writes frame N+2 while the GPU reads frame N.
    private static let maxFramesInFlight = 3
    private let frameSemaphore = DispatchSemaphore(value: maxFramesInFlight)
    private var instanceBuffers: [MTLBuffer] = []
    private var uniformBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private var instanceCapacity = 0

    /// Sprite images packed into array-texture pages.
    private var atlas: TextureAtlas?

    /// Whether the storyboard was authored for the wide stage.
    ///
    /// Decides both the projection and where storyboard x sits on it: a 4:3
    /// storyboard is drawn on the narrower stage rather than stretched across
    /// this one, which is what osu! does with it.
    public var isWidescreen = true

    /// Sprites are drawn in this order; layers are sorted bottom to top.
    private var drawOrder: [PreparedSprite] = []
    private var scratchStates: [SpriteRenderState] = []

    /// Sprite instances for the current frame, in storyboard draw order.
    private var instances: [SpriteInstance] = []

    /// A run of consecutive instances sharing one blend mode.
    private struct DrawBatch {
        let start: Int
        var count: Int
        let isAdditive: Bool
    }

    private var batches: [DrawBatch] = []

    /// Sprites drawn in the most recent frame, for on-screen diagnostics.
    public private(set) var lastDrawnCount = 0

    // ─── Setup ───────────────────────────────────────────────────────────────

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }
        commandQueue = queue

        let library = try Self.makeLibrary(device: device)

        guard let vertexFunction = library.makeFunction(name: "spriteVertex") else {
            throw RendererError.missingShaderFunction("spriteVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "spriteFragment") else {
            throw RendererError.missingShaderFunction("spriteFragment")
        }
        guard let untexturedFragment = library.makeFunction(name: "spriteFragmentUntextured") else {
            throw RendererError.missingShaderFunction("spriteFragmentUntextured")
        }

        normalPipeline = try Self.makePipeline(
            device: device, pixelFormat: pixelFormat,
            vertex: vertexFunction, fragment: fragmentFunction,
            blend: .normal, label: "Sprite/Normal",
        )
        additivePipeline = try Self.makePipeline(
            device: device, pixelFormat: pixelFormat,
            vertex: vertexFunction, fragment: fragmentFunction,
            blend: .additive, label: "Sprite/Additive",
        )
        untexturedPipeline = try Self.makePipeline(
            device: device, pixelFormat: pixelFormat,
            vertex: vertexFunction, fragment: untexturedFragment,
            blend: .normal, label: "Sprite/Untextured",
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        // Follows the atlas rather than being chosen here: filtering between
        // levels a texture does not have is undefined, and the hardware then
        // samples whatever it finds — which appears as detail the sprite never
        // had.
        samplerDescriptor.mipFilter = TextureAtlas.isMipmapped ? .linear : .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.samplerCreationFailed
        }
        samplerState = sampler

        for index in 0..<Self.maxFramesInFlight {
            guard let uniformBuffer = device.makeBuffer(
                length: MemoryLayout<Uniforms>.stride,
                options: .storageModeShared,
            ) else {
                throw RendererError.bufferAllocationFailed
            }
            uniformBuffer.label = "Uniforms[\(index)]"
            uniformBuffers.append(uniformBuffer)
        }

        try growInstanceBuffers(to: 4096)
    }

    /// Blend configurations. Additive is the one SpriteKit made awkward: here
    /// it is just a second pipeline with `.one`/`.one` factors.
    private enum BlendMode {
        case normal
        case additive
    }

    private static func makePipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        vertex: MTLFunction,
        fragment: MTLFunction,
        blend: BlendMode,
        label: String,
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment

        guard let attachment = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineCreationFailed(label)
        }
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add

        switch blend {
        case .normal:
            // Textures are premultiplied, so source colour is used as-is.
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        }

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Loads the shader library.
    ///
    /// SwiftPM copies `.metal` files into the resource bundle verbatim rather
    /// than compiling them, so a prebuilt `.metallib` only exists in an Xcode
    /// build. Prefer that when present, and otherwise compile the shader source
    /// at startup — which also makes shader edits visible on the next launch
    /// without a full rebuild.
    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }

        guard let url = Bundle.module.url(forResource: "Shaders", withExtension: "metal") else {
            throw RendererError.shaderLibraryUnavailable
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RendererError.shaderCompilationFailed(String(describing: error))
        }
    }

    // ─── Content ─────────────────────────────────────────────────────────────

    /// Sets the sprites to draw and uploads their textures.
    ///
    /// - Parameters:
    ///   - sprites: prepared sprites in storyboard order. They are grouped by
    ///     layer for drawing, and within a layer they keep the order given.
    ///   - textureProvider: supplies image data for a sprite's file path.
    ///     Returning `nil` draws that sprite as a flat tinted quad.
    public func setSprites(
        _ sprites: [PreparedSprite],
        textureProvider: (String) -> MTKTextureLoader.Source?,
    ) throws {
        // Sort by layer only, keeping file order within each one: a storyboard
        // declares its own back-to-front ordering, and additive sprites in
        // particular look wrong when that order changes.
        //
        // Swift's `sorted(by:)` is not guaranteed stable, so the original index
        // is the tie-breaker. Comparing ids would sort them as strings, putting
        // "sprite_10" before "sprite_9".
        drawOrder = sprites.enumerated()
            .sorted { lhs, rhs in
                lhs.element.layer.renderOrder == rhs.element.layer.renderOrder
                    ? lhs.offset < rhs.offset
                    : lhs.element.layer.renderOrder < rhs.element.layer.renderOrder
            }
            .map(\.element)

        // Rebuild the atlas only when the set of images actually changed.
        //
        // Editing an effect's parameters changes where its particles go, never
        // which files they use — and rebuilding means decoding every PNG in the
        // beatmap again, packing them, and uploading 4096² pages. That is a
        // visible stall on every drag of a slider, spent to arrive at the atlas
        // already on the GPU.
        //
        // This is the same split any compositor makes: the pixels of an asset
        // and the transform applied to them change for different reasons and at
        // different rates.
        let paths = Array(Set(sprites.map(\.filePath))).sorted()
        // Rebuild when the set of images changed, and also when the last build
        // could not find one of them: a path that resolved to nothing is drawn
        // as a flat quad, and the file it names is exactly the one someone is
        // about to drop into the folder. Without this the sprite stays a blank
        // square until the project is reopened, since the paths themselves
        // never changed.
        if paths != atlasPaths || atlas?.hasMissingTextures == true {
            try loadTextures(paths: paths, textureProvider: textureProvider)
            atlasPaths = paths
        }

        if drawOrder.count > instanceCapacity {
            try growInstanceBuffers(to: drawOrder.count)
        }
        scratchStates.reserveCapacity(drawOrder.count)
        instances.reserveCapacity(drawOrder.count)
    }

    /// The image paths the current atlas was built from, so an unchanged set
    /// can skip the rebuild.
    private var atlasPaths: [String] = []

    private func loadTextures(
        paths: [String],
        textureProvider: (String) -> MTKTextureLoader.Source?,
    ) throws {
        atlas = TextureAtlas(
            device: device,
            commandQueue: commandQueue,
            paths: paths,
            textureProvider: textureProvider,
        )
    }

    private func growInstanceBuffers(to count: Int) throws {
        let capacity = max(count, instanceCapacity * 2, 1024)
        instanceBuffers.removeAll(keepingCapacity: true)

        for index in 0..<Self.maxFramesInFlight {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<SpriteInstance>.stride * capacity,
                options: .storageModeShared,
            ) else {
                throw RendererError.bufferAllocationFailed
            }
            buffer.label = "Instances[\(index)]"
            instanceBuffers.append(buffer)
        }
        instanceCapacity = capacity
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    /// Resolves and draws every sprite alive at `time`.
    public func draw(at time: Double, in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable
        else { return }

        frameSemaphore.wait()
        frameIndex = (frameIndex + 1) % Self.maxFramesInFlight

        buildInstances(at: time)

        let instanceBuffer = instanceBuffers[frameIndex]
        let uniformBuffer = uniformBuffers[frameIndex]

        lastDrawnCount = instances.count

        if !instances.isEmpty {
            let pointer = instanceBuffer.contents().bindMemory(
                to: SpriteInstance.self,
                capacity: instanceCapacity,
            )
            instances.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                pointer.update(from: base, count: source.count)
            }
        }

        var uniforms = Uniforms(
            projection: Self.projectionMatrix(widescreen: isWidescreen),
        )
        uniformBuffer.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<Uniforms>.stride,
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            frameSemaphore.signal()
            return
        }

        encoder.label = "StoryboardPass"
        // Mirrored sprites have reversed winding, so both faces must draw.
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: Int(BufferIndexInstances.rawValue))
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
        encoder.setFragmentSamplerState(samplerState, index: 0)

        let textured = atlas != nil
        if let atlas {
            encoder.setFragmentTexture(atlas.texture, index: 0)
        }

        // Draw in storyboard order, switching pipeline only where the blend
        // mode changes. Drawing all normal sprites and then all additive ones
        // would be fewer state changes but wrong: a storyboard interleaves them
        // deliberately, and an additive flash must land under whatever the
        // storyboard draws after it.
        for batch in batches {
            let pipeline: MTLRenderPipelineState = if !textured {
                untexturedPipeline
            } else if batch.isAdditive {
                additivePipeline
            } else {
                normalPipeline
            }

            encoder.setRenderPipelineState(pipeline)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: batch.count,
                baseInstance: batch.start,
            )
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)

        commandBuffer.addCompletedHandler { [frameSemaphore] _ in
            frameSemaphore.signal()
        }
        commandBuffer.commit()
    }

    /// Turns resolved states into GPU instances, in storyboard draw order,
    /// recording where the blend mode changes so drawing can batch by run.
    private func buildInstances(at time: Double) {
        StoryboardResolver.resolve(drawOrder, at: time, into: &scratchStates)

        instances.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)

        // `resolve` preserves `drawOrder`, so walking both in step keeps the
        // per-sprite metadata aligned without a dictionary lookup.
        var spriteIndex = 0
        for state in scratchStates {
            while spriteIndex < drawOrder.count, drawOrder[spriteIndex].id != state.spriteId {
                spriteIndex += 1
            }
            guard spriteIndex < drawOrder.count else { break }
            let sprite = drawOrder[spriteIndex]
            spriteIndex += 1

            guard state.visible, state.opacity > 0 else { continue }

            // Sprites whose image is missing fall back to a small quad, so a
            // broken path is visible rather than silently absent.
            let entry = atlas?.entries[sprite.filePath]
            let size = entry?.pixelSize ?? SIMD2<Float>(100, 100)

            let scaledWidth = size.x * Float(state.scaleX)
            let scaledHeight = size.y * Float(state.scaleY)

            // Mirroring is a sign flip on the half-extent. The shader applies
            // the anchor to this same value, so a mirrored sprite stays pinned
            // to its origin.
            let halfSize = SIMD2<Float>(
                scaledWidth * 0.5 * (state.flipH ? -1 : 1),
                scaledHeight * 0.5 * (state.flipV ? -1 : 1),
            )

            let anchor = sprite.origin.anchor
            let opacity = Float(state.opacity)

            let instance = SpriteInstance(
                // The origin itself — the shader offsets the quad around it.
                position: SIMD2<Float>(
                    Float(state.x) + OsuCanvas.offset(widescreen: isWidescreen),
                    Float(state.y),
                ),
                halfSize: halfSize,
                anchor: SIMD2<Float>(anchor.x, anchor.y),
                rotation: Float(state.rotation),
                textureIndex: entry?.slice ?? 0,
                // Straight colour and alpha — the fragment shader premultiplies
                // once it has sampled the texture.
                color: SIMD4<Float>(
                    Float(state.r) / 255,
                    Float(state.g) / 255,
                    Float(state.b) / 255,
                    opacity,
                ),
                uvRect: entry?.uvRect ?? SIMD4<Float>(0, 0, 1, 1),
            )

            // Extend the open batch when the blend mode matches, else start one.
            if var last = batches.last, last.isAdditive == state.additive {
                last.count += 1
                batches[batches.count - 1] = last
            } else {
                batches.append(DrawBatch(
                    start: instances.count,
                    count: 1,
                    isAdditive: state.additive,
                ))
            }

            instances.append(instance)
        }
    }

    /// Orthographic projection from canvas space to clip space.
    ///
    /// Canvas space has Y increasing downwards; clip space has Y increasing
    /// upwards, so the Y row is negated.
    private static func projectionMatrix(widescreen: Bool) -> matrix_float4x4 {
        let (width, height) = OsuCanvas.size(widescreen: widescreen)

        return matrix_float4x4(columns: (
            SIMD4<Float>(2 / width, 0, 0, 0),
            SIMD4<Float>(0, -2 / height, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-1, 1, 0, 1),
        ))
    }
}

// ─── Errors ──────────────────────────────────────────────────────────────────

public enum RendererError: Error, CustomStringConvertible {
    case commandQueueCreationFailed
    case shaderLibraryUnavailable
    case shaderCompilationFailed(String)
    case missingShaderFunction(String)
    case pipelineCreationFailed(String)
    case samplerCreationFailed
    case bufferAllocationFailed
    case textureAllocationFailed
    case imageDecodingFailed

    public var description: String {
        switch self {
        case .commandQueueCreationFailed:
            "Could not create a Metal command queue."
        case .shaderLibraryUnavailable:
            "Could not find Shaders.metal in the renderer's resource bundle."
        case let .shaderCompilationFailed(reason):
            "Shader compilation failed: \(reason)"
        case let .missingShaderFunction(name):
            "Shader function '\(name)' is missing from the library."
        case let .pipelineCreationFailed(label):
            "Could not create the '\(label)' render pipeline state."
        case .samplerCreationFailed:
            "Could not create the texture sampler."
        case .bufferAllocationFailed:
            "Could not allocate a Metal buffer."
        case .textureAllocationFailed:
            "Could not allocate the sprite texture array."
        case .imageDecodingFailed:
            "Could not decode a sprite image."
        }
    }
}

// ─── Texture sources ─────────────────────────────────────────────────────────

extension MTKTextureLoader {
    /// Where a sprite's pixels come from.
    ///
    /// Images are decoded through Core Graphics into straight (non-premultiplied)
    /// RGBA rather than handed to `MTKTextureLoader` directly. The loader picks
    /// a pixel format from the file — often BGRA for images written on macOS —
    /// and the atlas assembles pages with a blit, which copies bytes without
    /// reordering channels. A BGRA source would land in an RGBA page with red
    /// and blue swapped, tinting every warm colour blue.
    public enum Source {
        case url(URL)
        case data(Data)

        /// Decodes the image into a `.rgba8Unorm` texture.
        func load(with loader: MTKTextureLoader) throws -> MTLTexture {
            guard let image = decodeImage() else {
                throw RendererError.imageDecodingFailed
            }
            return try Self.makeTexture(from: image, device: loader.device)
        }

        private func decodeImage() -> CGImage? {
            let source: CGImageSource? = switch self {
            case let .url(url): CGImageSourceCreateWithURL(url as CFURL, nil)
            case let .data(data): CGImageSourceCreateWithData(data as CFData, nil)
            }
            guard let source else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        /// Redraws the image into a known RGBA byte layout.
        ///
        /// Core Graphics handles whatever the source format was — indexed,
        /// greyscale, 16-bit, BGRA — and writes straight RGBA, which is what
        /// the shader premultiplies and the atlas expects.
        private static func makeTexture(from image: CGImage, device: MTLDevice) throws -> MTLTexture {
            let width = image.width
            let height = image.height
            let bytesPerRow = width * 4

            var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
            guard let context = pixels.withUnsafeMutableBytes({ buffer in
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    // sRGB explicitly, not `CGColorSpaceCreateDeviceRGB`.
                    //
                    // The device space is whatever the display happens to be,
                    // which on a modern Mac is a wide gamut: Core Graphics then
                    // converts a plain sRGB PNG into it and the colours come out
                    // pushed — more saturated than the file, and showing detail
                    // that was never meant to be visible. osu! composites in
                    // sRGB, so the pixels stay in the space they were authored
                    // in.
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue,
                )
            }) else {
                throw RendererError.imageDecodingFailed
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            // Follows the atlas: these textures are blitted into its pages, and
            // a blit copies bytes without interpreting them, so both sides have
            // to agree on what those bytes mean.
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: TextureAtlas.pixelFormat,
                width: width,
                height: height,
                mipmapped: false,
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared

            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.textureAllocationFailed
            }

            pixels.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: bytesPerRow,
                )
            }
            return texture
        }
    }
}
