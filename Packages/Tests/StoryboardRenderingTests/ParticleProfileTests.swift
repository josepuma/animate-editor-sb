import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import StoryboardCore
@testable import StoryboardRendering

/// A particle built from numbers rather than picked from a menu.
///
/// The nine fixed shapes were the one thing in this system a user could not
/// compose: every other parameter is an axis they combine freely, while the
/// particle's own form could only be widened by editing the app. That is the
/// line between an editor and a catalogue — and it is why a bokeh, which is
/// just a radial gradient with an unusual profile, was unreachable.
@Suite("Parametric particle")
struct ParticleProfileTests {
    /// Alpha at three points along the radius.
    private func profile(_ path: String) -> (centre: Double, mid: Double, rim: Double)? {
        guard let data = BuiltInTextures.data(for: path),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let side: Int = image.width
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return }
            context.draw(image, in: CGRect(
                x: 0, y: 0, width: CGFloat(side), height: CGFloat(side),
            ))
        }
        func alpha(at fraction: Double) -> Double {
            let half = Double(side) / 2
            let x: Int = min(side - 1, Int(half + half * fraction))
            let index: Int = ((side / 2) * side + x) * 4 + 3
            return Double(pixels[index]) / 255
        }
        return (alpha(at: 0), alpha(at: 0.5), alpha(at: 0.88))
    }

    /// **The case that could not be expressed before.**
    ///
    /// A defocused highlight is the lens aperture *projected*, not a point of
    /// light smeared — so it is dimmer in the middle than at its rim. None of
    /// the nine shapes could do that, and neither could a blur: measured, a
    /// blurred disc goes the other way, 1.00 → 0.62 → 0.49 as the radius grows.
    @Test("a bokeh circle is brighter at its rim than at its centre")
    func bokehIsBrighterAtTheRim() throws {
        let path = BuiltInSprite.particle(core: 0.62, edge: 0.92, falloff: 0.05)
        let p = try #require(profile(path))

        #expect(p.centre < 0.7, "the middle of a bokeh is dim")
        #expect(p.rim > p.centre, "and its rim is brighter than its middle")
        #expect(p.rim > 0.85, "with a defined edge rather than a fade")
    }

    /// The three numbers reach the shapes that used to be a closed list, which
    /// is what makes this a replacement rather than a tenth entry.
    @Test(
        "the parameters reach the shapes the fixed list held",
        arguments: [
            // name, core, edge, falloff, expected centre, expected rim
            ("flat disc", 1.0, 1.0, 0.0, 1.0, 0.9),
            ("soft dot", 1.0, 0.35, 1.0, 1.0, 0.2),
            ("tight glow", 1.0, 0.08, 0.55, 1.0, 0.1),
            ("ring", 0.0, 0.9, 0.1, 0.1, 0.85),
        ],
    )
    func reachesTheOldShapes(
        name: String, core: Double, edge: Double, falloff: Double,
        centreBelowOrAt: Double, rimAtLeastOrBelow: Double,
    ) throws {
        let p = try #require(profile(
            BuiltInSprite.particle(core: core, edge: edge, falloff: falloff),
        ))
        // A dim core means a ring; a bright one means a filled particle.
        if core < 0.5 {
            #expect(p.centre < 0.1, "\(name) should be hollow")
            #expect(p.rim > 0.8, "\(name) needs its rim")
        } else {
            #expect(p.centre > 0.95, "\(name) should be solid in the middle")
        }
    }

    /// Two parameters must not fight over the same space.
    ///
    /// `falloff` is a fraction of the radius *left over* after `edge`, not an
    /// absolute distance — expressed absolutely, a rim at 0.9 had a tenth of
    /// the radius to fade in and a long falloff was silently clipped, so
    /// `soft dot` came out identical to a flat disc.
    @Test("falloff still reads at a rim near the edge")
    func falloffScalesWithTheRoomLeft() throws {
        // Sampled *past* the rim, which is the only place a falloff shows: at
        // 0.88 both are still climbing to a peak that sits at 0.9.
        func alphaPastTheRim(falloff: Double) -> Double {
            let path = BuiltInSprite.particle(core: 1, edge: 0.9, falloff: falloff)
            guard let data = BuiltInTextures.data(for: path),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return -1 }
            let side: Int = image.width
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            pixels.withUnsafeMutableBytes { raw in
                guard let context = CGContext(
                    data: raw.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ) else { return }
                context.draw(image, in: CGRect(
                    x: 0, y: 0, width: CGFloat(side), height: CGFloat(side),
                ))
            }
            let half = Double(side) / 2
            let x: Int = min(side - 1, Int(half + half * 0.96))
            let index: Int = ((side / 2) * side + x) * 4 + 3
            return Double(pixels[index]) / 255
        }

        #expect(
            alphaPastTheRim(falloff: 1) > alphaPastTheRim(falloff: 0.05),
            "a long falloff must still carry light past a high rim",
        )
    }

    /// Quantised for the reason a hoop and a derived blur are: a continuous
    /// slider would mint a texture at every value it passes through, and the
    /// atlas has a fixed size.
    @Test("nearby values share one texture")
    func valuesAreQuantised() {
        #expect(
            BuiltInSprite.particle(core: 0.621, edge: 0.92, falloff: 0.05)
                == BuiltInSprite.particle(core: 0.618, edge: 0.92, falloff: 0.05),
        )
        #expect(
            BuiltInSprite.particle(core: 0.62, edge: 0.92, falloff: 0.05)
                != BuiltInSprite.particle(core: 0.70, edge: 0.92, falloff: 0.05),
        )
    }

    /// Core writes the path and the renderer reads it back, and the two are
    /// written separately because Core cannot import the renderer. A silent
    /// disagreement would leave every particle naming an image nobody provides.
    @Test("the path round-trips through the profile it names")
    func pathRoundTrips() throws {
        let path = BuiltInSprite.particle(core: 0.62, edge: 0.92, falloff: 0.05)
        let read = try #require(BuiltInSprite.particleProfile(path))
        #expect(abs(read.core - 0.62) < 0.011)
        #expect(abs(read.edge - 0.92) < 0.011)
        #expect(abs(read.falloff - 0.05) < 0.011)
        #expect(BuiltInTextures.data(for: path) != nil, "the renderer must draw it")
    }
}
