import CoreGraphics
import ImageIO
import Metal
import MetalKit
import simd

/// Packs sprite images into array-texture slices and records where each one landed.
///
/// A slice is only as useful as the region a sprite actually occupies, so every
/// entry carries the UV rectangle covering its pixels. Sampling the full slice
/// instead would stretch each image across the whole page.
struct TextureAtlas {
    /// Where one sprite's pixels live inside the array texture.
    struct Entry {
        /// Slice index within the array texture.
        let slice: UInt32
        /// UV rectangle covering the sprite: `(u0, v0, u1, v1)`.
        let uvRect: SIMD4<Float>
        /// Original pixel size, used to size the quad.
        let pixelSize: SIMD2<Float>
    }

    let texture: MTLTexture
    private(set) var entries: [String: Entry] = [:]

    /// Paths asked for that produced no texture.
    ///
    /// Kept so the renderer can tell "this atlas is complete" from "this atlas
    /// is missing files that may since have appeared". A sprite whose image is
    /// absent draws as a flat quad, which looks the same whether the file is
    /// genuinely gone or was added a second ago.
    private(set) var missingPaths: Set<String> = []

    var hasMissingTextures: Bool { !missingPaths.isEmpty }

    /// Page dimension.
    ///
    /// 4096 comfortably fits a 1920×1080 background alongside other sprites;
    /// every Metal GPU family supports at least this size for 2D arrays.
    static let pageSize = 4096

    /// What atlas pages, and the sprite textures blitted into them, are stored
    /// as.
    ///
    /// Plain `rgba8Unorm`, not the `_srgb` variant: osu! blends storyboards in
    /// gamma space, so the bytes are used as they stand. Converting to linear
    /// light and back is more correct in the abstract and does not match what
    /// the artwork was drawn against — overlaps darken and edges pick up a
    /// fringe.
    ///
    /// A blit copies bytes without interpreting them, so every texture that
    /// reaches a page has to be this format too.
    static let pixelFormat: MTLPixelFormat = .rgba8Unorm

    /// Whether atlas pages carry mipmaps.
    ///
    /// They do not: a storyboard scales its sprites up far more often than
    /// down, and building the chain for several 4096² pages costs memory and
    /// upload time for detail rarely asked for.
    ///
    /// The sampler has to agree. Filtering between levels that do not exist is
    /// undefined — the hardware samples whatever it finds, which appears as
    /// detail the sprite never had.
    static let isMipmapped = false

    /// Transparent gutter around each sprite.
    ///
    /// Linear filtering samples a texel's neighbours, so sprites packed edge to
    /// edge bleed into each other — every sprite picks up a border of whatever
    /// sits beside it on the page. The gutter gives the filter transparent
    /// pixels to blend with instead.
    static let padding = 2

    // ─── Building ────────────────────────────────────────────────────────────

    /// Loads and packs every path the provider can supply.
    ///
    /// Paths that fail to load are simply absent from ``entries``; the renderer
    /// draws those sprites as flat quads instead of failing the whole load.
    init?(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        paths: [String],
        textureProvider: (String) -> MTKTextureLoader.Source?,
    ) {
        let loader = MTKTextureLoader(device: device)

        // Load first, then pack: packing needs every size up front, and tall
        // images should be placed before short ones to reduce wasted rows.
        var loaded: [(path: String, texture: MTLTexture)] = []
        var missing: Set<String> = []
        for path in paths {
            guard let source = textureProvider(path),
                  let texture = try? source.load(with: loader)
            else {
                missing.insert(path)
                continue
            }
            loaded.append((path, texture))
        }
        guard !loaded.isEmpty else { return nil }

        loaded.sort { lhs, rhs in
            lhs.texture.height == rhs.texture.height
                ? lhs.texture.width > rhs.texture.width
                : lhs.texture.height > rhs.texture.height
        }

        var packer = ShelfPacker(pageSize: Self.pageSize)
        var placements: [(entry: (path: String, texture: MTLTexture), slot: ShelfPacker.Slot)] = []

        // Reserve the gutter as part of each sprite's footprint, so neighbours
        // are always at least `padding` texels apart.
        //
        // A sprite too large for a page is dropped rather than cropped — it
        // then renders as a flat quad, which is obvious, instead of as a
        // stretched image, which looks like an animation bug.
        for entry in loaded {
            guard let slot = packer.place(
                width: entry.texture.width + Self.padding * 2,
                height: entry.texture.height + Self.padding * 2,
            ) else {
                // Too large for a page. Recorded as missing so the sprite is
                // known to be drawing without its image, though rebuilding will
                // not help this one — only a smaller file will.
                missing.insert(entry.path)
                continue
            }
            placements.append((entry, slot))
        }
        guard !placements.isEmpty else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat,
            width: Self.pageSize,
            height: Self.pageSize,
            mipmapped: Self.isMipmapped,
        )
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = packer.pageCount
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private

        guard let atlas = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { return nil }

        atlas.label = "SpriteAtlas"

        // Pages start as uninitialised GPU memory, which samples as garbage in
        // the gaps between packed sprites. Zero every page before copying.
        let pageBytes = Self.pageSize * Self.pageSize * 4
        guard let clearBuffer = device.makeBuffer(
            length: pageBytes,
            options: .storageModeShared,
        ) else { return nil }
        memset(clearBuffer.contents(), 0, pageBytes)

        for page in 0..<packer.pageCount {
            blit.copy(
                from: clearBuffer,
                sourceOffset: 0,
                sourceBytesPerRow: Self.pageSize * 4,
                sourceBytesPerImage: pageBytes,
                sourceSize: MTLSize(width: Self.pageSize, height: Self.pageSize, depth: 1),
                to: atlas,
                destinationSlice: page,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            )
        }

        let inversePageSize = 1 / Float(Self.pageSize)
        for (entry, slot) in placements {
            // The slot includes the gutter; the pixels go inside it.
            let originX = slot.x + Self.padding
            let originY = slot.y + Self.padding
            let width = entry.texture.width
            let height = entry.texture.height

            // The packer guarantees the whole sprite fits, so a copy that would
            // run past the page edge means the two disagree. Skipping is the
            // safe response: copying part of a sprite while reporting its full
            // size stretches the image across the quad.
            guard originX + width <= Self.pageSize,
                  originY + height <= Self.pageSize
            else {
                assertionFailure("packer placed \(entry.path) outside its page")
                continue
            }

            blit.copy(
                from: entry.texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: atlas,
                destinationSlice: slot.page,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: originX, y: originY, z: 0),
            )

            // Inset the UV rectangle by half a texel so the sampler stays
            // within this sprite's pixels even at the very edge.
            let halfTexel = 0.5 * inversePageSize
            entries[entry.path] = Entry(
                slice: UInt32(slot.page),
                uvRect: SIMD4<Float>(
                    Float(originX) * inversePageSize + halfTexel,
                    Float(originY) * inversePageSize + halfTexel,
                    Float(originX + width) * inversePageSize - halfTexel,
                    Float(originY + height) * inversePageSize - halfTexel,
                ),
                pixelSize: SIMD2<Float>(
                    Float(entry.texture.width),
                    Float(entry.texture.height),
                ),
            )
        }

        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        texture = atlas
        missingPaths = missing
    }

    /// Number of slices in the array texture.
    var pageCount: Int { texture.arrayLength }
}

// ─── Packing ─────────────────────────────────────────────────────────────────

/// Shelf packer: fills a page row by row, opening a new page when full.
///
/// Simple and good enough for storyboards, where sprites tend to be small and
/// similar in height. It never revisits a closed shelf, trading some wasted
/// space for a single pass.
struct ShelfPacker {
    struct Slot {
        let page: Int
        let x: Int
        let y: Int
    }

    private let pageSize: Int
    private var page = 0
    private var shelfY = 0
    private var shelfHeight = 0
    private var cursorX = 0

    private(set) var pageCount = 1

    init(pageSize: Int) {
        self.pageSize = pageSize
    }

    /// Reserves space for `width` × `height`, opening shelves and pages as needed.
    ///
    /// - Returns: the slot, or `nil` when the sprite is larger than a whole
    ///   page and cannot be placed. Callers must skip those rather than copying
    ///   part of the image: a partial copy paired with the sprite's full size
    ///   stretches it across its quad.
    mutating func place(width: Int, height: Int) -> Slot? {
        guard width <= pageSize, height <= pageSize else { return nil }

        // Current shelf is full — start the next one.
        if cursorX + width > pageSize {
            shelfY += shelfHeight
            shelfHeight = 0
            cursorX = 0
        }

        // Page is full — start the next one.
        if shelfY + height > pageSize {
            page += 1
            pageCount = max(pageCount, page + 1)
            shelfY = 0
            shelfHeight = 0
            cursorX = 0
        }

        let slot = Slot(page: page, x: cursorX, y: shelfY)
        cursorX += width
        shelfHeight = max(shelfHeight, height)
        return slot
    }
}
