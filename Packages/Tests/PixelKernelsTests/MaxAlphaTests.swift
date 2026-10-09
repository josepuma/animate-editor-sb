import Testing

@testable import PixelKernels

/// The reduction behind the canvas's alpha masks: each cell keeps the most
/// opaque pixel that falls in it.
@Suite("Max alpha")
struct MaxAlphaTests {
    /// RGBA bytes, row by row from the top, with alpha set per pixel.
    private func rgba(width: Int, height: Int, alpha: (Int, Int) -> UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                bytes[(y * width + x) * 4 + 3] = alpha(x, y)
            }
        }
        return bytes
    }

    private func reduce(_ bytes: [UInt8], _ width: Int, _ height: Int, to mw: Int, _ mh: Int) -> [UInt8] {
        bytes.withUnsafeBytes {
            PixelKernels.maxAlpha($0, width: width, height: height, bytesPerRow: width * 4, toWidth: mw, height: mh)
        }
    }

    @Test("same size copies the alpha channel")
    func sameSize() {
        let out = reduce(rgba(width: 3, height: 2) { x, y in UInt8(x * 10 + y) }, 3, 2, to: 3, 2)
        #expect(out == [0, 10, 20, 1, 11, 21])
    }

    /// A one-pixel line in a big image is still something someone can point
    /// at. Averaging would fade it to nothing.
    @Test("each cell keeps its most opaque pixel")
    func keepsThinDetail() {
        let out = reduce(rgba(width: 8, height: 8) { x, _ in x == 5 ? 255 : 0 }, 8, 8, to: 2, 2)
        #expect(out == [0, 255, 0, 255])
    }

    /// Checked against a brute force over every cell, on a size that does not
    /// divide evenly.
    @Test("matches brute force on an uneven size")
    func bruteForce() {
        let (w, h, mw, mh) = (37, 23, 10, 7)
        let bytes = rgba(width: w, height: h) { x, y in UInt8((x * 31 + y * 17) % 256) }
        let out = reduce(bytes, w, h, to: mw, mh)
        for row in 0..<mh {
            for column in 0..<mw {
                var best: UInt8 = 0
                for y in 0..<h where y * mh / h == row {
                    for x in 0..<w where x * mw / w == column {
                        best = max(best, bytes[(y * w + x) * 4 + 3])
                    }
                }
                #expect(out[row * mw + column] == best, "cell \(column),\(row)")
            }
        }
    }
}
