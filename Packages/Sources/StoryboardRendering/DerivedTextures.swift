import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import StoryboardCore
import UniformTypeIdentifiers

/// Makes the images a derived sprite path names.
///
/// A glow asks for a blurred copy of whatever it surrounds. The source belongs
/// to the beatmap and cannot be touched, so the blurred version is produced
/// here and handed to the atlas as though it were any other texture.
public enum DerivedTextures {
    /// PNG data for a derived path, or `nil` when the path is not one.
    ///
    /// - Parameter source: supplies the original image for a path. Whoever
    ///   loads textures already knows how to find those, and it is not this
    ///   type's business whether the file came from the beatmap or the bundle.
    public static func data(for path: String, source: (String) -> Data?) -> Data? {
        guard let derived = DerivedSprite.parse(path) else { return nil }

        return cached(path) {
            switch derived.kind {
            case let .dotPanel(columns, rows, pitch, dotPercent, shape):
                // No source: a panel is only a lattice.
                return dotPanel(
                    columns: columns, rows: rows, pitch: pitch,
                    dotSize: Double(dotPercent) / 100, shape: shape,
                )
            case let .blur(radius):
                guard let original = source(derived.source) else { return nil }
                return blur(original, radius: radius)
            case let .dotMatrix(pitch, dotPercent, shape, thresholdPercent):
                guard let original = source(derived.source) else { return nil }
                return dotMatrix(
                    original, pitch: pitch, dotSize: Double(dotPercent) / 100,
                    shape: shape, threshold: Double(thresholdPercent) / 100,
                )
            }
        }
    }

    // ─── Dot matrix ──────────────────────────────────────────────────────────

    /// The source re-drawn as one hard-edged white dot per lit cell.
    ///
    /// The canvas is an even number of whole cells each way and the source sits
    /// in the middle of it — see ``DerivedSprite/cells(covering:pitch:)`` for
    /// why even, and why that is what lets the LED filter line dots up across
    /// separately rasterised glyphs without knowing any image's size.
    ///
    /// A cell lights when the source covers at least `threshold` of it, judged
    /// by mean alpha. The dot is drawn white with full alpha: colour comes from
    /// `_C` on the sprite, and a dot that fades with coverage would soften the
    /// very edge the look depends on.
    private static func dotMatrix(
        _ data: Data, pitch: Int, dotSize: Double,
        shape: DerivedSprite.DotShape, threshold: Double,
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let columns = DerivedSprite.cells(covering: Double(image.width), pitch: pitch)
        let rows = DerivedSprite.cells(covering: Double(image.height), pitch: pitch)
        let width = columns * pitch
        let height = rows * pitch

        // The source on a canvas of its own, to read coverage from. Centred with
        // whole pixels, so ink is never nudged by more than half of one.
        guard let reading = bitmap(width: width, height: height) else { return nil }
        reading.draw(image, in: CGRect(
            x: (width - image.width) / 2, y: (height - image.height) / 2,
            width: image.width, height: image.height,
        ))
        guard let pixels = reading.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let rowBytes = reading.bytesPerRow

        var lit: [(column: Int, row: Int)] = []
        for row in 0..<rows {
            for column in 0..<columns {
                var covered = 0
                // Memory row 0 is the top of the picture.
                for y in (row * pitch)..<((row + 1) * pitch) {
                    for x in (column * pitch)..<((column + 1) * pitch) {
                        covered += Int(pixels[y * rowBytes + x * 4 + 3])
                    }
                }
                let coverage = Double(covered) / Double(pitch * pitch * 255)
                if coverage >= threshold { lit.append((column, row)) }
            }
        }

        return drawDots(
            lit, width: width, height: height, pitch: pitch, dotSize: dotSize, shape: shape,
        )
    }

    /// Every cell of a `columns × rows` lattice lit: the unlit dots of a panel.
    private static func dotPanel(
        columns: Int, rows: Int, pitch: Int, dotSize: Double, shape: DerivedSprite.DotShape,
    ) -> Data? {
        let lit = (0..<rows).flatMap { row in (0..<columns).map { (column: $0, row: row) } }
        return drawDots(
            lit, width: columns * pitch, height: rows * pitch,
            pitch: pitch, dotSize: dotSize, shape: shape,
        )
    }

    private static func drawDots(
        _ cells: [(column: Int, row: Int)],
        width: Int, height: Int, pitch: Int, dotSize: Double,
        shape: DerivedSprite.DotShape,
    ) -> Data? {
        guard width > 0, height > 0, let context = bitmap(width: width, height: height)
        else { return nil }

        context.setAllowsAntialiasing(true)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        let diameter = Double(pitch) * dotSize
        for cell in cells {
            // CG's y grows upward and rows count from the top, so the row is
            // measured down from the canvas's height. Dots are symmetric, so
            // the flip cannot show — but the cell still has to be the right one.
            let rect = CGRect(
                x: (Double(cell.column) + 0.5) * Double(pitch) - diameter / 2,
                y: Double(height) - (Double(cell.row) + 0.5) * Double(pitch) - diameter / 2,
                width: diameter, height: diameter,
            )
            switch shape {
            case .round: context.fillEllipse(in: rect)
            case .square: context.fill(rect)
            }
        }

        guard let image = context.makeImage() else { return nil }
        return encode(image)
    }

    /// A premultiplied RGBA canvas, matching everything else that reaches the
    /// atlas.
    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
    }

    // ─── Blur ────────────────────────────────────────────────────────────────

    /// A Gaussian blur, on a canvas grown to hold the spread.
    ///
    /// The margin matters: a blur pushes light past the edges of its source,
    /// and on a canvas the same size as the original that light is simply cut
    /// off — the result is a soft image with hard sides, which reads as a
    /// rectangle rather than as a glow.
    private static func blur(_ data: Data, radius: Double) -> Data? {
        guard radius > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return data }

        let margin = Int((radius * 3).rounded())
        let width = image.width + margin * 2
        let height = image.height + margin * 2

        // Premultiplied, matching everything else that reaches the atlas.
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return data }

        context.draw(image, in: CGRect(
            x: margin, y: margin, width: image.width, height: image.height,
        ))
        guard let padded = context.makeImage() else { return data }

        let ciImage = CIImage(cgImage: padded)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return data }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        // Cropped back to the padded frame: a Gaussian blur reports an infinite
        // extent, and rendering that produces nothing usable.
        guard let output = filter.outputImage?.cropped(to: ciImage.extent),
              let rendered = ciContext.createCGImage(output, from: ciImage.extent)
        else { return data }

        return encode(rendered)
    }

    /// One context for the process.
    ///
    /// Building a `CIContext` compiles shaders and allocates GPU resources —
    /// several hundred milliseconds. Made per call, a slider drag would spend
    /// all of its time here.
    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
    ])

    // ─── Cache ───────────────────────────────────────────────────────────────

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Data] = [:]

    /// Blurring is expensive and a texture is asked for once per sprite —
    /// hundreds of times for one emitter, and again on every re-evaluation.
    private static func cached(_ key: String, make: () -> Data?) -> Data? {
        lock.lock()
        if let existing = cache[key] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        // Made outside the lock: blurring a large image takes long enough that
        // holding it would stall every other texture load behind this one.
        guard let made = make() else { return nil }

        lock.lock()
        cache[key] = made
        lock.unlock()
        return made
    }

    /// Drops cached images, for when a project closes.
    public static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
