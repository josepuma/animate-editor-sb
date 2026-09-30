#!/usr/bin/env swift
// Converts a greyscale-on-black spotlight picture into the built-in `strobe`
// texture: white, with the light carried in alpha.
//
//   swift scripts/make-strobe-texture.swift ~/Documents/strobe.png \
//       Packages/Sources/StoryboardRendering/Particles/strobe.png
//
// Every built-in is white with an alpha profile so `_C` decides the colour. The
// source is fully opaque — grey light over solid black — and dropped in as-is
// it would draw a black rectangle in normal blend mode. So the luminance
// becomes the alpha, normalised so the brightest pixel is fully opaque.
//
// Size is kept as-is (no padding): the atlas shelf-packs any size with its own
// transparent gutter, and the source already fades to zero on every side.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-strobe-texture <source.png> <output.png>\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fatalError("cannot read \(input.path)") }

let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)

// Decoded through Core Graphics like the renderer does, so "luminance" here is
// the same byte the game would have sampled.
let decoded: Bool = pixels.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard decoded else { fatalError("cannot decode") }

// Rec. 709 weights; the source is pure grey so they all agree, but a tinted
// source would otherwise be read unevenly.
func luminance(_ index: Int) -> Double {
    0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
}

var peak = 0.0
for pixel in 0..<(width * height) { peak = max(peak, luminance(pixel * 4)) }
guard peak > 0 else { fatalError("source is entirely black") }

// Straight (non-premultiplied) output, which is what a PNG stores.
var result = [UInt8](repeating: 255, count: width * height * 4)
for pixel in 0..<(width * height) {
    result[pixel * 4 + 3] = UInt8((luminance(pixel * 4) / peak * 255).rounded())
}

let provider = CGDataProvider(data: Data(result) as CFData)!
guard let converted = CGImage(
    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("cannot encode") }

CGImageDestinationAddImage(destination, converted, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(output.path)") }
print("wrote \(output.path) \(width)x\(height), peak luminance \(peak)")
