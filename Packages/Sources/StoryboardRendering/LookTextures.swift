import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore

/// The images behind the Look filters: outline, halftone, duotone and ink.
///
/// Plain pixel loops over Core Graphics bitmaps, no Core Image. They run once
/// per path and are cached, so speed matters less than being exact and
/// testable without a GPU — and a CI runner has none.
enum LookTextures {
    // ─── Outline ─────────────────────────────────────────────────────────────

    /// The source's silhouette grown by `width`, white, on a canvas grown by
    /// the margin Core undoes when it places the copy.
    ///
    /// Grown by true distance, so corners round: a box-shaped dilation reads
    /// as a chunky offset rather than a line drawn around the shape.
    static func outline(_ data: Data, width: Int) -> Data? {
        guard let image = decode(data) else { return nil }
        let margin = DerivedSprite.outlineMargin(width: Double(width))
        guard var pixels = Pixels(image: image, padding: margin) else { return nil }

        let inside = pixels.alphas.map { $0 >= 0.5 }
        let distance = DistanceField.toNearest(inside, width: pixels.width, height: pixels.height)

        for index in pixels.alphas.indices {
            // One pixel of falloff past the width, for an antialiased edge.
            let ring = min(1, max(0, Double(width) + 0.5 - distance[index]))
            pixels.setWhite(index, alpha: max(ring, pixels.alphas[index]))
        }
        return pixels.encoded()
    }

    // ─── Halftone ────────────────────────────────────────────────────────────

    /// One white dot per `cell` pixels, its area proportional to the cell's
    /// ink — alpha times luminance, so a dim region screens lighter.
    static func halftone(_ data: Data, cell: Int, shape: DerivedSprite.DotShape) -> Data? {
        guard let image = decode(data), let pixels = Pixels(image: image, padding: 0),
              let context = DerivedTextures.bitmap(width: pixels.width, height: pixels.height)
        else { return nil }

        context.setAllowsAntialiasing(true)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        let columns = (pixels.width + cell - 1) / cell
        let rows = (pixels.height + cell - 1) / cell
        for row in 0..<rows {
            for column in 0..<columns {
                var ink = 0.0
                var count = 0
                for y in (row * cell)..<min((row + 1) * cell, pixels.height) {
                    for x in (column * cell)..<min((column + 1) * cell, pixels.width) {
                        let index = y * pixels.width + x
                        ink += pixels.alphas[index] * pixels.luminance(index)
                        count += 1
                    }
                }
                let fill = count > 0 ? ink / Double(count) : 0
                guard fill > 0.004 else { continue }

                // Area, not radius, follows the ink: that is what makes a
                // screen read as a grey level. Full ink reaches the cell's
                // corners, so solid regions close up as print does.
                let side = Double(cell) * fill.squareRoot()
                let size = shape == .round ? side * 2.squareRoot() : side
                let centreX = (Double(column) + 0.5) * Double(cell)
                // CG's y grows upward; rows count from the top.
                let centreY = Double(pixels.height) - (Double(row) + 0.5) * Double(cell)
                let rect = CGRect(x: centreX - size / 2, y: centreY - size / 2, width: size, height: size)
                switch shape {
                case .round: context.fillEllipse(in: rect)
                case .square: context.fill(rect)
                }
            }
        }
        guard let made = context.makeImage() else { return nil }
        return DerivedTextures.encode(made)
    }

    // ─── Duotone ─────────────────────────────────────────────────────────────

    /// Each pixel's luminance mapped from `dark` to `light`, alpha kept.
    static func duotone(_ data: Data, dark: Int, light: Int) -> Data? {
        guard let image = decode(data), var pixels = Pixels(image: image, padding: 0) else { return nil }
        let from = channels(dark)
        let to = channels(light)
        for index in pixels.alphas.indices {
            let l = pixels.luminance(index)
            pixels.set(index, rgb: (
                from.r + (to.r - from.r) * l,
                from.g + (to.g - from.g) * l,
                from.b + (to.b - from.b) * l,
            ), alpha: pixels.alphas[index])
        }
        return pixels.encoded()
    }

    // ─── Ink ─────────────────────────────────────────────────────────────────

    /// White lines `width` wide along the silhouette's contour and, as far as
    /// `detail` allows, along the edges inside it.
    ///
    /// The canvas stays the source's size, so the anchor stays put; a line on
    /// the very border of the picture loses its outer half, which only matters
    /// for an image whose ink touches its own edge.
    static func ink(_ data: Data, width: Int, detail: Double) -> Data? {
        guard let image = decode(data), var pixels = Pixels(image: image, padding: 0) else { return nil }
        let w = pixels.width
        let h = pixels.height
        let inside = pixels.alphas.map { $0 >= 0.5 }

        // Seeds: inside pixels with an outside neighbour, plus — with any
        // detail at all — inside pixels where the shading changes sharply.
        let ink = pixels.alphas.indices.map { pixels.alphas[$0] * pixels.luminance($0) }
        // Sobel peaks at 4 on a 0–1 step; full detail draws faint edges, a
        // little detail only the strong ones.
        let threshold = 0.2 + (1 - detail) * 3.6
        var seeds = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let index = y * w + x
                guard inside[index] else { continue }
                let border = x == 0 || y == 0 || x == w - 1 || y == h - 1
                    || !inside[index - 1] || !inside[index + 1] || !inside[index - w] || !inside[index + w]
                if border {
                    seeds[index] = true
                    continue
                }
                guard detail > 0 else { continue }
                let at = { (dx: Int, dy: Int) in ink[(y + dy) * w + (x + dx)] }
                let gx = (at(1, -1) + 2 * at(1, 0) + at(1, 1)) - (at(-1, -1) + 2 * at(-1, 0) + at(-1, 1))
                let gy = (at(-1, 1) + 2 * at(0, 1) + at(1, 1)) - (at(-1, -1) + 2 * at(0, -1) + at(1, -1))
                if (gx * gx + gy * gy).squareRoot() >= threshold { seeds[index] = true }
            }
        }

        let distance = DistanceField.toNearest(seeds, width: w, height: h)
        let half = Double(width) / 2
        for index in pixels.alphas.indices {
            let alpha = min(1, max(0, half + 0.5 - distance[index]))
            pixels.setWhite(index, alpha: alpha)
        }
        return pixels.encoded()
    }

    // ─── Tile ────────────────────────────────────────────────────────────────

    /// One cell of a grid over the source, everything else cleared, on the
    /// source's own canvas. Cell edges are whole pixels and the cells tile
    /// the canvas exactly, so the pieces of a shatter add back up to the
    /// original with no seam and no overlap.
    static func tile(_ data: Data, columns: Int, rows: Int, index: Int) -> Data? {
        guard let image = decode(data), var pixels = Pixels(image: image, padding: 0) else { return nil }
        let column = index % max(columns, 1)
        let row = index / max(columns, 1)
        let left = pixels.width * column / columns
        let right = pixels.width * (column + 1) / columns
        let top = pixels.height * row / rows
        let bottom = pixels.height * (row + 1) / rows
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where !(x >= left && x < right && y >= top && y < bottom) {
                pixels.clear(y * pixels.width + x)
            }
        }
        return pixels.encoded()
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func channels(_ hex: Int) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// A premultiplied RGBA canvas read into numbers, with the source drawn at a
/// whole-pixel padding. Memory row 0 is the top of the picture.
private struct Pixels {
    let width: Int
    let height: Int
    private var bytes: [UInt8]
    /// Alpha per pixel, 0–1.
    private(set) var alphas: [Double]

    init?(image: CGImage, padding: Int) {
        // Locals, not `self`: the closure below runs before every property
        // is set, and Swift will not let it capture a half-built value.
        let w = image.width + padding * 2
        let h = image.height + padding * 2
        guard w > 0, h > 0 else { return nil }
        width = w
        height = h
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer
        alphas = stride(from: 3, to: buffer.count, by: 4).map { Double(buffer[$0]) / 255 }
    }

    /// Luminance of the un-premultiplied colour, 0–1.
    func luminance(_ index: Int) -> Double {
        let alpha = alphas[index]
        guard alpha > 0 else { return 0 }
        let base = index * 4
        let r = Double(bytes[base]) / 255 / alpha
        let g = Double(bytes[base + 1]) / 255 / alpha
        let b = Double(bytes[base + 2]) / 255 / alpha
        return min(1, 0.2126 * r + 0.7152 * g + 0.0722 * b)
    }

    mutating func clear(_ index: Int) {
        let base = index * 4
        bytes[base] = 0
        bytes[base + 1] = 0
        bytes[base + 2] = 0
        bytes[base + 3] = 0
        alphas[index] = 0
    }

    mutating func setWhite(_ index: Int, alpha: Double) {
        set(index, rgb: (1, 1, 1), alpha: alpha)
    }

    mutating func set(_ index: Int, rgb: (Double, Double, Double), alpha: Double) {
        let base = index * 4
        let byte = { (value: Double) in UInt8(min(255, max(0, (value * alpha * 255).rounded()))) }
        bytes[base] = byte(rgb.0)
        bytes[base + 1] = byte(rgb.1)
        bytes[base + 2] = byte(rgb.2)
        bytes[base + 3] = UInt8(min(255, max(0, (alpha * 255).rounded())))
        alphas[index] = alpha
    }

    func encoded() -> Data? {
        var buffer = bytes
        let image: CGImage? = buffer.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )?.makeImage()
        }
        return image.flatMap(DerivedTextures.encode)
    }
}

/// Exact Euclidean distance to the nearest marked pixel, in pixels.
///
/// Felzenszwalb and Huttenlocher's two-pass transform: linear in the pixel
/// count whatever the distance, where growing a shape by stamping copies costs
/// the square of the width.
enum DistanceField {
    static func toNearest(_ marked: [Bool], width: Int, height: Int) -> [Double] {
        let far = 1e20
        var squared = marked.map { $0 ? 0 : far }

        var column = [Double](repeating: 0, count: height)
        for x in 0..<width {
            for y in 0..<height { column[y] = squared[y * width + x] }
            let done = transform(column)
            for y in 0..<height { squared[y * width + x] = done[y] }
        }
        var row = [Double](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width { row[x] = squared[y * width + x] }
            let done = transform(row)
            for x in 0..<width { squared[y * width + x] = done[x] }
        }
        return squared.map { $0.squareRoot() }
    }

    /// One dimension: the lower envelope of parabolas rooted at each sample.
    private static func transform(_ f: [Double]) -> [Double] {
        let n = f.count
        guard n > 0 else { return [] }
        var d = [Double](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Double](repeating: 0, count: n + 1)
        var k = 0
        z[0] = -.infinity
        z[1] = .infinity
        for q in 1..<max(n, 1) {
            var s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            while s <= z[k] {
                k -= 1
                s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .infinity
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            let dq = Double(q - v[k])
            d[q] = dq * dq + f[v[k]]
        }
        return d
    }
}
