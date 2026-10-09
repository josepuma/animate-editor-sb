/// The per-pixel loops behind the derived Look textures, over premultiplied
/// RGBA bytes with row 0 at the top.
///
/// A target of its own for one reason: it is compiled with optimisation even
/// in a debug build (see `Package.swift`). `swift run` is a debug build, and
/// unoptimised Swift neither inlines nor specialises — every subscript, even
/// on an unsafe buffer, is a generic call. Measured on a 1920×1080 image, Ink
/// took **3.2 seconds** in debug against 70ms in release, all of it on the
/// main thread the canvas loads textures on. Rewriting the loops tighter only
/// got that to 2.3; turning the optimiser on is what removes the cost.
///
/// Depends on nothing, so it can be optimised without dragging anything else
/// along, and stays small enough that debugging it unoptimised is never
/// needed. No closures cross into it: a closure from another module is not
/// inlined, and a per-pixel call is the cost this target exists to avoid.
public enum PixelKernels {
    // ─── Alpha masks ─────────────────────────────────────────────────────────

    /// Shrinks an image's alpha to `toWidth` × `height`, each cell keeping the
    /// most opaque pixel that falls in it — so a one-pixel line survives where
    /// an average would fade it out. RGBA bytes, row 0 at the top.
    public static func maxAlpha(
        _ bytes: UnsafeRawBufferPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        toWidth maskWidth: Int,
        height maskHeight: Int,
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        guard width > 0, height > 0, maskWidth > 0, maskHeight > 0 else { return out }
        // The cell each column falls in, worked out once rather than per pixel.
        var columnCell = [Int](repeating: 0, count: width)
        for x in 0..<width { columnCell[x] = min(maskWidth - 1, x * maskWidth / width) }

        out.withUnsafeMutableBufferPointer { out in
            columnCell.withUnsafeBufferPointer { columnCell in
                for y in 0..<height {
                    let rowStart = min(maskHeight - 1, y * maskHeight / height) * maskWidth
                    let source = y * bytesPerRow + 3
                    for x in 0..<width {
                        let value = bytes[source + x * 4]
                        let index = rowStart + columnCell[x]
                        if value > out[index] { out[index] = value }
                    }
                }
            }
        }
        return out
    }

    // ─── Outline ─────────────────────────────────────────────────────────────

    /// Every pixel white, at the larger of its own alpha and a ring that
    /// falls from 1 to 0 between `reach − 1` and `reach` pixels from the
    /// silhouette (alpha ≥ ½).
    public static func outline(_ bytes: inout [UInt8], width: Int, height: Int, reach: Double) {
        let distance = distanceToNearest(inside(bytes, count: width * height), width: width, height: height)
        bytes.withUnsafeMutableBufferPointer { bytes in
            distance.withUnsafeBufferPointer { distance in
                for i in 0..<distance.count {
                    let base = i * 4
                    let own = Double(bytes[base + 3]) / 255
                    let ring = min(1, max(0, reach - distance[i]))
                    let byte = UInt8(min(255, max(0, (max(ring, own) * 255).rounded())))
                    bytes[base] = byte
                    bytes[base + 1] = byte
                    bytes[base + 2] = byte
                    bytes[base + 3] = byte
                }
            }
        }
    }

    // ─── Ink ─────────────────────────────────────────────────────────────────

    /// White lines along the silhouette's contour and, where `threshold`
    /// lets them in, along sharp changes of shading inside it — each line
    /// falling off `reach` pixels from its seed.
    ///
    /// - Parameter threshold: Sobel magnitude an inner edge needs; `nil`
    ///   draws the contour alone.
    public static func ink(_ bytes: inout [UInt8], width w: Int, height h: Int, reach: Double, threshold: Double?) {
        let count = w * h
        let inside = inside(bytes, count: count)
        let ink = ink(bytes, count: count)
        var seeds = [Bool](repeating: false, count: count)
        let squared = threshold.map { $0 * $0 }

        inside.withUnsafeBufferPointer { inside in
            ink.withUnsafeBufferPointer { ink in
                seeds.withUnsafeMutableBufferPointer { seeds in
                    for y in 0..<h {
                        for x in 0..<w {
                            let i = y * w + x
                            guard inside[i] else { continue }
                            if x == 0 || y == 0 || x == w - 1 || y == h - 1
                                || !inside[i - 1] || !inside[i + 1] || !inside[i - w] || !inside[i + w]
                            {
                                seeds[i] = true
                                continue
                            }
                            guard let squared else { continue }
                            let up = i - w
                            let down = i + w
                            let gx = (ink[up + 1] + 2 * ink[i + 1] + ink[down + 1]) - (ink[up - 1] + 2 * ink[i - 1] + ink[down - 1])
                            let gy = (ink[down - 1] + 2 * ink[down] + ink[down + 1]) - (ink[up - 1] + 2 * ink[up] + ink[up + 1])
                            if gx * gx + gy * gy >= squared { seeds[i] = true }
                        }
                    }
                }
            }
        }

        let distance = distanceToNearest(seeds, width: w, height: h)
        bytes.withUnsafeMutableBufferPointer { bytes in
            distance.withUnsafeBufferPointer { distance in
                for i in 0..<count {
                    let base = i * 4
                    let byte = UInt8(min(255, max(0, (min(1, max(0, reach - distance[i])) * 255).rounded())))
                    bytes[base] = byte
                    bytes[base + 1] = byte
                    bytes[base + 2] = byte
                    bytes[base + 3] = byte
                }
            }
        }
    }

    // ─── Duotone ─────────────────────────────────────────────────────────────

    /// Each pixel's luminance mapped from `from` to `to` (channels 0–1),
    /// alpha kept.
    public static func duotone(
        _ bytes: inout [UInt8], count: Int,
        from: (r: Double, g: Double, b: Double), to: (r: Double, g: Double, b: Double),
    ) {
        bytes.withUnsafeMutableBufferPointer { bytes in
            for i in 0..<count {
                let base = i * 4
                let alpha = Double(bytes[base + 3]) / 255
                guard alpha > 0 else { continue }
                let l = min(1, luminance(bytes, base) / alpha)
                let premultiply = alpha * 255
                bytes[base] = UInt8(min(255, max(0, ((from.r + (to.r - from.r) * l) * premultiply).rounded())))
                bytes[base + 1] = UInt8(min(255, max(0, ((from.g + (to.g - from.g) * l) * premultiply).rounded())))
                bytes[base + 2] = UInt8(min(255, max(0, ((from.b + (to.b - from.b) * l) * premultiply).rounded())))
            }
        }
    }

    // ─── Halftone ────────────────────────────────────────────────────────────

    /// The mean ink — alpha times luminance — of each `cell × cell` block,
    /// row by row; edge cells average only the pixels they hold.
    public static func cellInk(_ bytes: [UInt8], width w: Int, height h: Int, cell: Int) -> (fills: [Double], columns: Int, rows: Int) {
        let columns = (w + cell - 1) / cell
        let rows = (h + cell - 1) / cell
        var sums = [Double](repeating: 0, count: columns * rows)
        var counts = [Int](repeating: 0, count: columns * rows)
        bytes.withUnsafeBufferPointer { bytes in
            sums.withUnsafeMutableBufferPointer { sums in
                counts.withUnsafeMutableBufferPointer { counts in
                    for y in 0..<h {
                        let cellRow = (y / cell) * columns
                        for x in 0..<w {
                            let base = (y * w + x) * 4
                            let at = cellRow + x / cell
                            sums[at] += min(Double(bytes[base + 3]) / 255, luminance(bytes, base))
                            counts[at] += 1
                        }
                    }
                }
            }
        }
        let fills = zip(sums, counts).map { $1 > 0 ? $0 / Double($1) : 0 }
        return (fills, columns, rows)
    }

    // ─── Tile ────────────────────────────────────────────────────────────────

    /// Clears every pixel outside `left..<right × top..<bottom`.
    public static func clear(_ bytes: inout [UInt8], width w: Int, height h: Int, keeping rect: (left: Int, right: Int, top: Int, bottom: Int)) {
        bytes.withUnsafeMutableBufferPointer { bytes in
            for y in 0..<h {
                let keepRow = y >= rect.top && y < rect.bottom
                for x in 0..<w where !(keepRow && x >= rect.left && x < rect.right) {
                    let base = (y * w + x) * 4
                    bytes[base] = 0
                    bytes[base + 1] = 0
                    bytes[base + 2] = 0
                    bytes[base + 3] = 0
                }
            }
        }
    }

    // ─── Distance ────────────────────────────────────────────────────────────

    /// Exact Euclidean distance from each pixel to the nearest marked one.
    ///
    /// Felzenszwalb and Huttenlocher's two-pass transform: linear in the
    /// pixel count whatever the distance, where growing a shape by stamping
    /// copies costs the square of the width. Scratch buffers are shared by
    /// every row and column rather than allocated per line.
    public static func distanceToNearest(_ marked: [Bool], width: Int, height: Int) -> [Double] {
        let n = max(width, height)
        var squared = [Double](repeating: 1e20, count: width * height)
        var f = [Double](repeating: 0, count: n)
        var d = [Double](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Double](repeating: 0, count: n + 1)

        marked.withUnsafeBufferPointer { marked in
            squared.withUnsafeMutableBufferPointer { squared in
                for i in 0..<marked.count where marked[i] { squared[i] = 0 }
                f.withUnsafeMutableBufferPointer { f in
                    d.withUnsafeMutableBufferPointer { d in
                        v.withUnsafeMutableBufferPointer { v in
                            z.withUnsafeMutableBufferPointer { z in
                                for x in 0..<width {
                                    for y in 0..<height { f[y] = squared[y * width + x] }
                                    envelope(f, d, v, z, count: height)
                                    for y in 0..<height { squared[y * width + x] = d[y] }
                                }
                                for y in 0..<height {
                                    let line = y * width
                                    for x in 0..<width { f[x] = squared[line + x] }
                                    envelope(f, d, v, z, count: width)
                                    for x in 0..<width { squared[line + x] = d[x] }
                                }
                            }
                        }
                    }
                }
                for i in 0..<squared.count { squared[i] = squared[i].squareRoot() }
            }
        }
        return squared
    }

    /// One dimension: the lower envelope of parabolas rooted at each sample,
    /// `f` in, `d` out, over the first `n` entries.
    private static func envelope(
        _ f: UnsafeMutableBufferPointer<Double>, _ d: UnsafeMutableBufferPointer<Double>,
        _ v: UnsafeMutableBufferPointer<Int>, _ z: UnsafeMutableBufferPointer<Double>, count n: Int,
    ) {
        guard n > 0 else { return }
        var k = 0
        v[0] = 0
        z[0] = -.infinity
        z[1] = .infinity
        var q = 1
        while q < n {
            let fq = f[q] + Double(q * q)
            var s = (fq - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            while s <= z[k] {
                k -= 1
                s = (fq - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .infinity
            q += 1
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            let dq = Double(q - v[k])
            d[q] = dq * dq + f[v[k]]
        }
    }

    // ─── Reading ─────────────────────────────────────────────────────────────

    /// Whether each pixel is at least half covered: the silhouette.
    private static func inside(_ bytes: [UInt8], count: Int) -> [Bool] {
        var result = [Bool](repeating: false, count: count)
        bytes.withUnsafeBufferPointer { bytes in
            result.withUnsafeMutableBufferPointer { result in
                for i in 0..<count { result[i] = bytes[i * 4 + 3] >= 128 }
            }
        }
        return result
    }

    /// Alpha times the un-premultiplied luminance, capped at full — on a
    /// premultiplied pixel, the stored channels' own luminance, no division.
    private static func ink(_ bytes: [UInt8], count: Int) -> [Double] {
        var result = [Double](repeating: 0, count: count)
        bytes.withUnsafeBufferPointer { bytes in
            result.withUnsafeMutableBufferPointer { result in
                for i in 0..<count {
                    let base = i * 4
                    result[i] = min(Double(bytes[base + 3]) / 255, luminance(bytes, base))
                }
            }
        }
        return result
    }

    /// Rec. 709 luminance of a pixel's stored (premultiplied) channels, 0–1.
    @inline(__always)
    private static func luminance<Bytes: RandomAccessCollection>(_ bytes: Bytes, _ base: Int) -> Double
        where Bytes.Element == UInt8, Bytes.Index == Int
    {
        (0.2126 * Double(bytes[base]) + 0.7152 * Double(bytes[base + 1]) + 0.0722 * Double(bytes[base + 2])) / 255
    }
}
