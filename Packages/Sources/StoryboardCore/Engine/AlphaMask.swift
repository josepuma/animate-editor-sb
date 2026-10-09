import Foundation

/// A small copy of an image's transparency, for telling what a pointer is over.
///
/// Picking by a sprite's box made a glow, or a PNG with a wide clear margin,
/// a wall in front of everything that showed through it. What is picked has to
/// be what is seen, so the hit test reads the image's alpha — kept here, on the
/// CPU, because the texture itself lives on the GPU.
///
/// Shrunk to `maximumSide` on its longest side: a few kilobytes per image, and
/// finer than any pointer aims. Each cell keeps its *most* opaque pixel rather
/// than the average, so a one-pixel line survives the shrink
/// (`PixelKernels.maxAlpha`).
public struct AlphaMask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row by row from the top, the way the texture is uploaded.
    public let alpha: [UInt8]

    public static let maximumSide = 64

    public init(width: Int, height: Int, alpha: [UInt8]) {
        self.width = width
        self.height = height
        self.alpha = alpha
    }

    /// The mask's size for an image: the image's own, or shrunk so its
    /// longest side is `maximumSide`, never below a pixel.
    ///
    /// The reduction itself is a per-pixel loop over the whole image, so it
    /// lives in `PixelKernels`, which is optimised even in a debug build:
    /// here, unoptimised, a 2048² image took 575ms at load.
    public static func size(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height, 1)
        let ratio = min(1, Double(maximumSide) / Double(longest))
        return (
            max(1, Int((Double(width) * ratio).rounded())),
            max(1, Int((Double(height) * ratio).rounded())),
        )
    }

    /// The opacity at a texture coordinate, 0…1, or 0 outside the image.
    public func alpha(u: Double, v: Double) -> Double {
        guard u >= 0, u <= 1, v >= 0, v <= 1, !alpha.isEmpty else { return 0 }
        let x = min(width - 1, Int(u * Double(width)))
        let y = min(height - 1, Int(v * Double(height)))
        return Double(alpha[y * width + x]) / 255
    }
}
