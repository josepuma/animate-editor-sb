import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing

@testable import StoryboardRendering

/// A shape that fades along a direction.
///
/// The ramp is in **alpha**, never in colour: every built-in image is drawn
/// white and tinted by its `_C` command, so one texture serves every colour and
/// the tint stays animatable. Baking two colours in would mint a texture per
/// pair and take the colour out of the author's hands.
@Suite("Gradient shape")
struct GradientShapeTests {
    private func image(
        shape: BuiltInSprite.GradientShape = .square,
        angle: Double, start: Double, end: Double,
    ) throws -> CGImage {
        let path = BuiltInSprite.gradient(shape: shape, angle: angle, start: start, end: end)
        let data = try #require(BuiltInTextures.data(for: path), "no image for \(path)")
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(_ image: CGImage) throws -> (data: [UInt8], width: Int) {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (buffer, width)
    }

    private func alpha(_ p: (data: [UInt8], width: Int), x: Int, y: Int) -> Double {
        Double(p.data[(y * p.width + x) * 4 + 3]) / 255
    }

    /// The whole point: opaque at one end, gone at the other.
    @Test("a gradient fades from opaque to clear across its axis")
    func fadesAcross() throws {
        let p = try pixels(try image(angle: 0, start: 0, end: 1))
        let mid = p.width / 2

        let left = alpha(p, x: 2, y: mid)
        let right = alpha(p, x: p.width - 3, y: mid)

        #expect(left > 0.9, "the near end is solid")
        #expect(right < 0.1, "the far end is gone")
    }

    /// It has to be monotonic, or it is not a ramp.
    @Test("the ramp only ever decreases along its axis")
    func rampIsMonotonic() throws {
        let p = try pixels(try image(angle: 0, start: 0, end: 1))
        let mid = p.width / 2

        var previous = 1.01
        for x in stride(from: 2, to: p.width - 2, by: 8) {
            let value = alpha(p, x: x, y: mid)
            #expect(value <= previous + 0.02, "alpha rose at x=\(x)")
            previous = value
        }
    }

    /// The angle turns the ramp. At 90° it runs vertically, so a horizontal
    /// scan is flat — the check that catches an angle silently ignored.
    @Test("the angle turns the ramp")
    func angleTurnsIt() throws {
        let p = try pixels(try image(angle: 90, start: 0, end: 1))
        let mid = p.width / 2

        let acrossLeft = alpha(p, x: 2, y: mid)
        let acrossRight = alpha(p, x: p.width - 3, y: mid)
        #expect(abs(acrossLeft - acrossRight) < 0.05, "flat across the axis")

        let top = alpha(p, x: mid, y: 2)
        let bottom = alpha(p, x: mid, y: p.width - 3)
        #expect(abs(top - bottom) > 0.8, "and ramped along it")
    }

    /// The stops say *where* the fade happens; outside them the shape is held
    /// solid or clear rather than ceasing to exist.
    @Test("the stops hold the shape solid before and clear after")
    func stopsHoldOutside() throws {
        let p = try pixels(try image(angle: 0, start: 0.4, end: 0.6))
        let mid = p.width / 2

        #expect(alpha(p, x: Int(Double(p.width) * 0.1), y: mid) > 0.9, "solid before the first stop")
        #expect(alpha(p, x: Int(Double(p.width) * 0.9), y: mid) < 0.1, "clear after the last")
    }

    /// A shape is judged by where it ends. `fill` is edge to edge for that
    /// reason and this is too: a soft margin would stretch with the bar until
    /// its ends came out faded.
    @Test("the solid end reaches the edge of the image")
    func solidEndIsHardEdged() throws {
        let p = try pixels(try image(angle: 0, start: 0.5, end: 1))
        let mid = p.width / 2

        #expect(alpha(p, x: 0, y: mid) > 0.9)
        #expect(alpha(p, x: 0, y: 0) > 0.9, "including its corner")
    }

    /// Stops that do not advance are a hard edge, and a zero-length gradient is
    /// undefined — it has to still produce an image.
    @Test("equal stops still draw")
    func equalStopsDraw() throws {
        let p = try pixels(try image(angle: 0, start: 0.5, end: 0.5))
        let mid = p.width / 2

        #expect(alpha(p, x: 2, y: mid) > 0.9)
        #expect(alpha(p, x: p.width - 3, y: mid) < 0.1)
    }

    /// **Core writes the path and the renderer reads it back**, and the two are
    /// written separately because `StoryboardCore` sits below the renderer and
    /// cannot import it. A disagreement would leave the shape naming an image
    /// nobody provides — a bare quad with nothing to explain it.
    @Test("every quantised path round-trips into an image")
    func pathsRoundTrip() throws {
        for angle in stride(from: 0.0, to: 360, by: 15) {
            for start in [0.0, 0.25, 0.5] {
                let path = BuiltInSprite.gradient(shape: .square, angle: angle, start: start, end: 1)
                let profile = try #require(
                    BuiltInSprite.gradientProfile(path), "\(path) did not parse",
                )
                #expect(profile.angle == angle)
                #expect(abs(profile.start - start) < 0.001)
                #expect(BuiltInTextures.data(for: path) != nil, "no image for \(path)")
            }
        }
    }

    /// Coarse on purpose, and this is what keeps the atlas finite: three axes
    /// multiply, and a continuous slider would mint a texture at every value it
    /// passes through. Fifteen degrees of difference in a soft ramp is not a
    /// difference anyone can see.
    @Test("nearby values share one texture")
    func quantisation() {
        #expect(
            BuiltInSprite.gradient(shape: .square, angle: 3, start: 0, end: 1)
                == BuiltInSprite.gradient(shape: .square, angle: 11, start: 0, end: 1),
        )
        #expect(
            BuiltInSprite.gradient(shape: .square, angle: 0, start: 0.21, end: 1)
                == BuiltInSprite.gradient(shape: .square, angle: 0, start: 0.19, end: 1),
        )
        #expect(
            BuiltInSprite.gradient(shape: .square, angle: 0, start: 0, end: 1)
                != BuiltInSprite.gradient(shape: .square, angle: 45, start: 0, end: 1),
        )
    }

    /// The fade rides on the shape rather than replacing it. Drawing the ramp
    /// alone gives a rectangle whatever shape was asked for, which is the
    /// failure this catches: a disc has to keep its transparent corners.
    @Test("a gradient on a circle is still a circle")
    func circleKeepsItsShape() throws {
        let p = try pixels(try image(shape: .circle, angle: 0, start: 0.9, end: 1))
        let mid = p.width / 2

        #expect(alpha(p, x: mid, y: mid) > 0.9, "solid through the middle")
        #expect(alpha(p, x: 1, y: 1) < 0.1, "and empty in the corner")
    }

    /// A hoop keeps its hole, which the disc test cannot show.
    @Test("a gradient on a ring is still a ring")
    func ringKeepsItsHole() throws {
        let path = BuiltInSprite.gradient(
            shape: .ring, angle: 0, start: 0.9, end: 1,
        )
        let data = try #require(BuiltInTextures.data(for: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let p = try pixels(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        let mid = p.width / 2

        #expect(alpha(p, x: mid, y: mid) < 0.1, "hollow in the middle")
        #expect(alpha(p, x: 4, y: mid) > 0.5, "and drawn on its rim")
    }

    /// Each shape is its own texture, or a circle and a square would collide on
    /// one path and whichever was generated first would answer for both.
    @Test("each shape gets its own path")
    func shapesDoNotCollide() {
        let square = BuiltInSprite.gradient(shape: .square, angle: 0, start: 0, end: 1)
        let circle = BuiltInSprite.gradient(shape: .circle, angle: 0, start: 0, end: 1)

        #expect(square != circle)
        #expect(BuiltInSprite.gradientProfile(square)?.shape == .square)
        #expect(BuiltInSprite.gradientProfile(circle)?.shape == .circle)
    }

    /// A ring's weight is drawn into its image, so two thicknesses cannot share
    /// a path — the same rule the plain hoop already follows.
    @Test("a ring's thickness is part of its path")
    func ringThicknessIsInThePath() throws {
        let thin = BuiltInSprite.gradient(
            shape: .ring, angle: 0, start: 0, end: 1, thickness: 0.05,
        )
        let thick = BuiltInSprite.gradient(
            shape: .ring, angle: 0, start: 0, end: 1, thickness: 0.4,
        )

        #expect(thin != thick)
        let profile = try #require(BuiltInSprite.gradientProfile(thick))
        #expect(abs(profile.thickness - 0.4) < 0.001)
    }

    /// **The gradient has to be the size Core scales by.**
    ///
    /// `BuiltInSprite.gradientSourceSize` states that number and cannot see the
    /// renderer, so a texture drawn at its own convenient size would come out
    /// scaled by the wrong factor — with nothing on screen to explain it.
    ///
    /// It is larger than a plain square for a reason that is about the stretch
    /// rather than the shape: at 64 texels a ramp advances four to six levels
    /// per texel, which is a visible kink every 13 pixels once it is blown up.
    @Test(
        "a faded shape is drawn at the size Core scales by",
        arguments: BuiltInSprite.GradientShape.allCases,
    )
    func gradientMatchesItsShapeSize(shape: BuiltInSprite.GradientShape) throws {
        let image = try decoded(try #require(BuiltInTextures.data(
            for: BuiltInSprite.gradient(shape: shape, angle: 0, start: 0, end: 1),
        )))

        #expect(Double(image.width) == BuiltInSprite.gradientSourceSize)
        #expect(Double(image.height) == BuiltInSprite.gradientSourceSize)
    }

    private func decoded(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// **The banding is born in the stretch, not in the texture.**
    ///
    /// A ramp is stored in 8 bits. At 64 texels each one advances four to six
    /// levels, and blown up to a full-width bar that is 13 pixels between
    /// neighbours with the interpolation running straight between them — so the
    /// slope changes abruptly at every texel, and those kinks read as bands.
    ///
    /// The fix is texels, not noise: sub-level dither was tried and cannot hide
    /// a jump of six levels. This measures the jump, which is what has to be
    /// small — under two levels puts the kinks below what the eye resolves once
    /// the shape is stretched across the stage.
    @Test("the ramp advances gently enough not to band")
    func rampDoesNotBand() throws {
        let p = try pixels(try image(angle: 0, start: 0, end: 1))
        let row = p.width / 2

        var worst = 0
        for x in 4..<(p.width - 4) {
            let here = Int(alpha(p, x: x, y: row) * 255)
            let next = Int(alpha(p, x: x + 1, y: row) * 255)
            worst = max(worst, abs(here - next))
        }

        #expect(worst <= 2, "a texel jumped \(worst) levels — that is a visible kink")
    }

    /// Solid and clear are exact. Noise there would fray an edge that has to
    /// stay clean — a bar whose ends went ragged.
    @Test("dither leaves the flat ends alone")
    func ditherSparesTheEnds() throws {
        let p = try pixels(try image(angle: 0, start: 0.4, end: 0.6))
        let row = p.width / 2

        for x in 0..<8 {
            #expect(alpha(p, x: x, y: row) == 1, "the solid end got noisy")
        }
        for x in (p.width - 8)..<p.width {
            #expect(alpha(p, x: x, y: row) == 0, "the clear end got noisy")
        }
    }

    /// A texture cached from an earlier draw and one drawn now have to be the
    /// same image, so the noise is seeded rather than random.
    @Test("the dither is deterministic")
    func ditherRepeats() throws {
        let path = BuiltInSprite.gradient(shape: .square, angle: 0, start: 0, end: 1)
        let first = try #require(BuiltInTextures.data(for: path))
        let second = try #require(BuiltInTextures.data(for: path))

        #expect(first == second)
    }

    /// **Core names the shape and the renderer draws it**, with the two lists
    /// written separately because `StoryboardCore` sits below the renderer and
    /// cannot import it. A name on one side that the other does not know falls
    /// back to a rectangle — which is how a gradient on a ring came out solid.
    @Test("every gradient shape names a shape the renderer draws")
    func shapeNamesAgree() {
        for shape in BuiltInSprite.GradientShape.allCases {
            #expect(
                BuiltInTextures.Shape(rawValue: shape.rawValue) != nil,
                "the renderer has no shape called \(shape.rawValue)",
            )
        }
    }

    /// An angle past a full turn is the same direction, and a negative one is
    /// too — a path that disagreed would mint a second texture for a ramp
    /// already drawn.
    @Test("angles wrap around the circle")
    func anglesWrap() {
        #expect(
            BuiltInSprite.gradient(shape: .square, angle: 30, start: 0, end: 1)
                == BuiltInSprite.gradient(shape: .square, angle: 390, start: 0, end: 1),
        )
        #expect(
            BuiltInSprite.gradient(shape: .square, angle: 345, start: 0, end: 1)
                == BuiltInSprite.gradient(shape: .square, angle: -15, start: 0, end: 1),
        )
    }
}
