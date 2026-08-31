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
            guard let original = source(derived.source) else { return nil }

            switch derived.kind {
            case let .blur(radius):
                return blur(original, radius: radius)
            }
        }
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
