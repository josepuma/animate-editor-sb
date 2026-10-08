#!/usr/bin/env swift
// Extracts every sampled brush tip from a Photoshop brush file (`.abr`) as a
// white PNG whose shape lives in alpha — the same form as every built-in, so
// `_C` decides the colour.
//
//   swift scripts/abr-to-png.swift <brushes.abr> <output-folder>
//
// Only version 6+ files (Photoshop CS onwards) are read: the tips live in the
// `8BIMsamp` section, each a greyscale mask where 255 is full paint. Computed
// brushes (round tips described by parameters) carry no image and never appear
// in that section, so they are skipped by construction.
//
// The mask is copied straight into alpha, without normalising: a soft brush
// that peaks at 60% is a soft brush, and stretching it to 255 would change it.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: abr-to-png <brushes.abr> <output-folder>\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let outputFolder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let data = try? Data(contentsOf: input) else { fatalError("cannot read \(input.path)") }
let bytes = [UInt8](data)

struct Reader {
    let bytes: [UInt8]
    var offset: Int

    var remaining: Int { bytes.count - offset }

    mutating func u8() -> UInt8 {
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16() -> Int {
        Int(u8()) << 8 | Int(u8())
    }

    mutating func u32() -> Int {
        u16() << 16 | u16()
    }

    mutating func i32() -> Int {
        Int(Int32(bitPattern: UInt32(u32())))
    }

    mutating func tag() -> String {
        defer { offset += 4 }
        return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
    }
}

var header = Reader(bytes: bytes, offset: 0)
let version = header.u16()
let subversion = header.u16()
guard version >= 6, subversion == 1 || subversion == 2 else {
    fatalError("unsupported .abr version \(version).\(subversion) — only v6+ (subversion 1 or 2) is read")
}

// Sections are `8BIM` + four-letter key + length; only `samp` holds tips.
var sampRange: Range<Int>?
while header.remaining >= 12 {
    guard header.tag() == "8BIM" else { fatalError("corrupt section header at \(header.offset - 4)") }
    let key = header.tag()
    let length = header.u32()
    if key == "samp" { sampRange = header.offset..<(header.offset + length) }
    header.offset += length
}
guard let sampRange else { fatalError("no sampled brushes in \(input.lastPathComponent)") }

/// PackBits: a signed count byte, then either `n + 1` literal bytes or one
/// byte repeated `1 − n` times. −128 is a no-op.
func unpackBits(_ reader: inout Reader, compressedLength: Int, into row: inout [UInt8]) {
    let end = reader.offset + compressedLength
    var written = 0
    while reader.offset < end, written < row.count {
        let count = Int(Int8(bitPattern: reader.u8()))
        if count >= 0 {
            for _ in 0...count where written < row.count {
                row[written] = reader.u8()
                written += 1
            }
        } else if count != -128 {
            let value = reader.u8()
            for _ in 0..<(1 - count) where written < row.count {
                row[written] = value
                written += 1
            }
        }
    }
    reader.offset = end
}

func writePNG(alpha: [UInt8], width: Int, height: Int, to url: URL) {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for pixel in 0..<(width * height) { rgba[pixel * 4 + 3] = alpha[pixel] }
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    guard let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
    ), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot encode \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
}

try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
let baseName = input.deletingPathExtension().lastPathComponent

var reader = Reader(bytes: bytes, offset: sampRange.lowerBound)
var index = 0
while reader.offset + 4 <= sampRange.upperBound {
    let size = reader.u32()
    // Each sample is padded to four bytes; the next one starts after the pad.
    let next = reader.offset + (size + 3) / 4 * 4

    // Sample id (Pascal string) plus fields we don't need: 47 bytes in
    // subversion 1, 301 in subversion 2 — the layout GIMP's loader uses.
    reader.offset += subversion == 1 ? 47 : 301
    let top = reader.i32(), left = reader.i32(), bottom = reader.i32(), right = reader.i32()
    let depth = reader.u16()
    let compression = reader.u8()
    let width = right - left, height = bottom - top
    guard width > 0, height > 0, depth == 8 || depth == 16 else {
        print("skipped sample \(index + 1): \(width)x\(height), depth \(depth)")
        reader.offset = next
        index += 1
        continue
    }

    let bytesPerPixel = depth / 8
    let rowBytes = width * bytesPerPixel
    var raw = [UInt8](repeating: 0, count: rowBytes * height)
    if compression == 1 {
        let lengths = (0..<height).map { _ in reader.u16() }
        var row = [UInt8](repeating: 0, count: rowBytes)
        for y in 0..<height {
            unpackBits(&reader, compressedLength: lengths[y], into: &row)
            raw.replaceSubrange((y * rowBytes)..<((y + 1) * rowBytes), with: row)
        }
    } else {
        raw.replaceSubrange(0..<raw.count, with: bytes[reader.offset..<(reader.offset + raw.count)])
    }

    // 16-bit masks are big-endian: the high byte is the 8-bit value.
    let alpha = bytesPerPixel == 1 ? raw : stride(from: 0, to: raw.count, by: 2).map { raw[$0] }

    index += 1
    let url = outputFolder.appendingPathComponent(String(format: "%@-%02d.png", baseName, index))
    writePNG(alpha: alpha, width: width, height: height, to: url)
    print("wrote \(url.lastPathComponent) \(width)x\(height)")
    reader.offset = next
}
