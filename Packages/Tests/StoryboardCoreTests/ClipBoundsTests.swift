import Foundation
import Testing

@testable import StoryboardCore

@Suite("Clip bounds")
struct ClipBoundsTests {
    private func state(
        _ id: String, x: Double, y: Double,
        scale: Double = 1, rotation: Double = 0, opacity: Double = 1,
        flipH: Bool = false, flipV: Bool = false,
    ) -> SpriteRenderState {
        SpriteRenderState(
            spriteId: id, x: x, y: y,
            scaleX: scale, scaleY: scale,
            rotation: rotation, opacity: opacity,
            r: 255, g: 255, b: 255,
            visible: true, additive: false, flipH: flipH, flipV: flipV,
        )
    }

    private let size: (String) -> (width: Double, height: Double)? = { _ in (100, 50) }

    @Test("the box contains every sprite")
    func spansEverything() throws {
        let box = try #require(ClipBounds.around([
            state("a", x: 100, y: 100),
            state("b", x: 300, y: 200),
        ], sizeOf: size))

        #expect(box.minX == 50)   // 100 - half of 100
        #expect(box.maxX == 350)  // 300 + half of 100
        #expect(box.minY == 75)   // 100 - half of 50
        #expect(box.maxY == 225)
    }

    // ─── Origin ──────────────────────────────────────────────────────────────

    /// **The bug this pins.** The box assumed every sprite hangs centred on
    /// its position, which is one origin out of nine. A `CentreLeft` sprite
    /// draws to the *right* of its position, so the frame sat a half width to
    /// its left — beside the picture rather than around it.
    @Test("the box follows the sprite's origin")
    func originShiftsTheBox() throws {
        let box = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100)],
            sizeOf: size,
            originOf: { _ in .centreLeft },
        ))

        // The image starts at the position and runs right.
        #expect(box.minX == 100)
        #expect(box.maxX == 200)
        // Vertically still centred, which is what CentreLeft means.
        #expect(box.minY == 75)
        #expect(box.maxY == 125)
    }

    @Test("the default origin is centred, as it always measured")
    func defaultIsCentre() throws {
        let box = try #require(ClipBounds.around([state("a", x: 100, y: 100)], sizeOf: size))

        #expect(box.minX == 50)
        #expect(box.maxX == 150)
    }

    /// Every origin, against the same expression the vertex shader uses. A box
    /// derived from a second reading of the anchor would drift from the
    /// picture the moment either changed.
    @Test(
        "every origin places the box where the shader draws the sprite",
        arguments: Origin.allCases,
    )
    func everyOriginMatchesTheShader(origin: Origin) throws {
        let box = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100)],
            sizeOf: size,
            originOf: { _ in origin },
        ))

        // (0.5 - anchor) * 2 * halfSize, straight from Shaders.metal.
        let halfWidth = 50.0, halfHeight = 25.0
        let centreX = 100 + (0.5 - Double(origin.anchor.x)) * 2 * halfWidth
        let centreY = 100 + (0.5 - Double(origin.anchor.y)) * 2 * halfHeight

        #expect(abs(box.minX - (centreX - halfWidth)) < 1e-9)
        #expect(abs(box.maxX - (centreX + halfWidth)) < 1e-9)
        #expect(abs(box.minY - (centreY - halfHeight)) < 1e-9)
        #expect(abs(box.maxY - (centreY + halfHeight)) < 1e-9)
    }

    /// A corner origin moves the box on both axes at once — the case a
    /// single-axis check would let through.
    @Test("a corner origin shifts both axes")
    func cornerShiftsBoth() throws {
        let box = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100)],
            sizeOf: size,
            originOf: { _ in .topLeft },
        ))

        #expect(box.minX == 100)
        #expect(box.minY == 100)
        #expect(box.maxX == 200)
        #expect(box.maxY == 150)
    }

    /// The offset scales with the sprite, because the anchor is applied to the
    /// half-extent after scaling — computing it on the unscaled size leaves the
    /// frame drifting further off the larger the clip gets.
    @Test("the origin offset scales with the sprite")
    func offsetScales() throws {
        let box = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100, scale: 3)],
            sizeOf: size,
            originOf: { _ in .centreLeft },
        ))

        #expect(box.minX == 100)
        #expect(box.maxX == 400)  // 100 wide, tripled
    }

    /// **A flip turns the image over INSIDE its own box.**
    ///
    /// osu! keeps the box where origin plus position put it and mirrors the
    /// pixels within. A `TopCentre` bar at y=480 hangs off the bottom of the
    /// frame flipped or not — the box never swings to the other side of the
    /// origin, which is what the renderer used to do and why a mirrored bottom
    /// bar was visible in the editor and gone in the game.
    @Test("a flip never moves the box, for any origin", arguments: Origin.allCases)
    func flipIsInPlace(origin: Origin) throws {
        let plain = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100)], sizeOf: size, originOf: { _ in origin },
        ))

        for (h, v) in [(true, false), (false, true), (true, true)] {
            let flipped = try #require(ClipBounds.around(
                [state("a", x: 100, y: 100, flipH: h, flipV: v)],
                sizeOf: size, originOf: { _ in origin },
            ))
            #expect(flipped.minX == plain.minX && flipped.maxX == plain.maxX, "\(origin) h=\(h) v=\(v)")
            #expect(flipped.minY == plain.minY && flipped.maxY == plain.maxY, "\(origin) h=\(h) v=\(v)")
        }
    }

    @Test("a horizontally flipped CentreLeft sprite still runs right from its position")
    func flipKeepsTheSide() throws {
        let mirrored = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100, flipH: true)],
            sizeOf: size, originOf: { _ in .centreLeft },
        ))
        #expect(mirrored.minX == 100)
    }

    @Test("a vertically flipped TopCentre sprite still hangs downward")
    func verticalFlipKeepsTheSide() throws {
        let mirrored = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100, flipV: true)],
            sizeOf: size, originOf: { _ in .topCentre },
        ))
        #expect(mirrored.minY == 100)
    }

    /// A resize preview has to grow the way the sprite grows.
    ///
    /// **The bug this pins.** The frame grew about the centre of the box while
    /// the sprite scales about its anchor, so with `CentreLeft` the preview
    /// spread evenly to both sides and the release committed a clip that had
    /// grown only rightwards. The frame lied about what the drag would do.
    ///
    /// Measured through the bounds rather than the view: scaling a
    /// `CentreLeft` sprite must leave its left edge exactly where it was.
    @Test("scaling a left-anchored sprite keeps its left edge")
    func scalingHoldsTheAnchor() throws {
        let before = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100)],
            sizeOf: size,
            originOf: { _ in .centreLeft },
        ))
        let after = try #require(ClipBounds.around(
            [state("a", x: 100, y: 100, scale: 2)],
            sizeOf: size,
            originOf: { _ in .centreLeft },
        ))

        #expect(after.minX == before.minX, "the anchored edge stays put")
        #expect(after.maxX > before.maxX, "it grows away from the anchor")
    }

    /// The centred case still grows both ways, which is what it always did.
    @Test("scaling a centred sprite grows both ways")
    func scalingCentredGrowsBothWays() throws {
        let before = try #require(ClipBounds.around([state("a", x: 100, y: 100)], sizeOf: size))
        let after = try #require(
            ClipBounds.around([state("a", x: 100, y: 100, scale: 2)], sizeOf: size),
        )

        #expect(after.minX < before.minX)
        #expect(after.maxX > before.maxX)
    }

    /// The box is measured upright and turned by the caller, so its size does
    /// not change with the angle.
    ///
    /// Growing it to cover the rotated extent is correct about containment and
    /// wrong about what it communicates: at 45° an upright box swells to about
    /// 1.41× and shrinks back at 90°, so a steady spin reads as the clip
    /// pulsing. The angle travels with the box instead.
    @Test("a rotated sprite keeps its measured size")
    func rotationDoesNotResizeTheBox() throws {
        let flat = try #require(ClipBounds.around([state("a", x: 320, y: 240)], sizeOf: size))
        let turned = try #require(ClipBounds.around(
            [state("a", x: 320, y: 240, rotation: .pi / 2)], sizeOf: size,
        ))

        #expect(abs(turned.width - flat.width) < 0.001)
        #expect(abs(turned.height - flat.height) < 0.001)
        #expect(abs(turned.rotation - .pi / 2) < 0.001)
    }

    @Test("scale grows the box")
    func scaleGrowsTheBox() throws {
        let small = try #require(ClipBounds.around([state("a", x: 320, y: 240)], sizeOf: size))
        let large = try #require(ClipBounds.around(
            [state("a", x: 320, y: 240, scale: 2)], sizeOf: size,
        ))

        #expect(abs(large.width - small.width * 2) < 0.001)
    }

    /// Invisible sprites are not on screen, so a box around them would point at
    /// nothing.
    @Test("invisible sprites are ignored")
    func invisibleSpritesAreSkipped() {
        #expect(ClipBounds.around([state("a", x: 0, y: 0, opacity: 0)], sizeOf: size) == nil)
    }

    /// A missing image must not collapse the box: the sprite is still
    /// somewhere, and reporting nothing would hide a clip that exists.
    @Test("a sprite with no known size still contributes its position")
    func unknownSizesStillCount() throws {
        let box = try #require(ClipBounds.around([
            state("a", x: 100, y: 100),
            state("b", x: 200, y: 150),
        ], sizeOf: { _ in nil }))

        #expect(box.minX == 100)
        #expect(box.maxX == 200)
    }

    /// The separator is what stops a node claiming its neighbour's sprites:
    /// without it, `node1` would own everything `node10` made.
    @Test("a clip owns its own sprites and no one else's")
    func ownership() {
        #expect(ClipBounds.sprite("node1/p0", belongsTo: "node1"))
        #expect(ClipBounds.sprite("node1", belongsTo: "node1"))
        #expect(!ClipBounds.sprite("node10/p0", belongsTo: "node1"))
        #expect(!ClipBounds.sprite("other/p0", belongsTo: "node1"))
    }

    @Test("nothing selected is no box")
    func emptyIsNil() {
        #expect(ClipBounds.around([], sizeOf: size) == nil)
    }
}

@Suite("Clip bounds rotation")
struct ClipBoundsRotationTests {
    private func state(_ id: String, rotation: Double) -> SpriteRenderState {
        SpriteRenderState(
            spriteId: id, x: 320, y: 240,
            scaleX: 1, scaleY: 1, rotation: rotation, opacity: 1,
            r: 255, g: 255, b: 255,
            visible: true, additive: false, flipH: false, flipV: false,
        )
    }

    private let size: (String) -> (width: Double, height: Double)? = { _ in (100, 50) }

    /// The box keeps one size through a turn, and reports the angle instead.
    ///
    /// Folding rotation into an upright box swelled it to about 1.41× at 45°
    /// and back at 90°, so a clip spinning at a steady rate looked like it was
    /// pulsing — right about what it contained, wrong about what it showed.
    @Test("a turning clip keeps its size and reports its angle")
    func rotationIsReportedNotFolded() throws {
        let upright = try #require(ClipBounds.around([state("a", rotation: 0)], sizeOf: size))
        let turned = try #require(ClipBounds.around(
            [state("a", rotation: .pi / 4)], sizeOf: size,
        ))

        #expect(abs(turned.width - upright.width) < 0.001)
        #expect(abs(turned.height - upright.height) < 0.001)
        #expect(abs(turned.rotation - .pi / 4) < 0.001)
    }

    /// A particle field turning every which way has no one angle to draw.
    @Test("sprites at different angles report none")
    func disagreeingAnglesReportNone() throws {
        let box = try #require(ClipBounds.around([
            state("a", rotation: 0),
            state("b", rotation: .pi / 2),
        ], sizeOf: size))

        #expect(box.rotation == 0)
    }
}

@Suite("Clip bounds of turned sprites")
struct ClipBoundsTurnedTests {
    private func state(
        _ id: String, x: Double, y: Double, scale: Double = 1, rotation: Double,
    ) -> SpriteRenderState {
        SpriteRenderState(spriteId: id, x: x, y: y, scaleX: scale, scaleY: scale, rotation: rotation)
    }

    private let size: (String) -> (width: Double, height: Double)? = { _ in (100, 50) }

    /// osu! turns a sprite about its origin. The box used to shift by the
    /// origin in upright axes and then be turned about its own centre, so a
    /// stretched `TopLeft` bar turned 30° had its frame tens of pixels away
    /// from the picture — reported after stretching a shape and rotating it.
    @Test("a rotated sprite's box is centred where osu! draws it", arguments: [
        Origin.topLeft, .topCentre, .centreLeft, .bottomRight, .centre,
    ])
    func rotatedOriginCentre(origin: Origin) throws {
        let angle = 30 * Double.pi / 180
        let box = try #require(ClipBounds.around(
            [state("a", x: 300, y: 200, scale: 2, rotation: angle)],
            sizeOf: size,
            originOf: { _ in origin },
        ))

        // The sprite's centre: its position plus the origin's offset, turned.
        let anchor = origin.anchor
        let ox = (0.5 - Double(anchor.x)) * 200, oy = (0.5 - Double(anchor.y)) * 100
        let cx = 300 + ox * cos(angle) - oy * sin(angle)
        let cy = 200 + ox * sin(angle) + oy * cos(angle)

        #expect(abs(box.centreX - cx) < 1e-9 && abs(box.centreY - cy) < 1e-9,
                "centre (\(box.centreX), \(box.centreY)) against (\(cx), \(cy))")
        #expect(abs(box.width - 200) < 1e-9 && abs(box.height - 100) < 1e-9)
        #expect(box.rotation == angle)
    }

    /// Two sprites sharing an angle are framed in their own axes: two bars
    /// end to end along a turned line make one long turned frame, not the
    /// upright box around them.
    @Test("sprites sharing an angle union in their own axes")
    func sharedAngleUnion() throws {
        let angle = 30 * Double.pi / 180
        let step = 100.0
        let box = try #require(ClipBounds.around([
            state("a", x: 300, y: 200, rotation: angle),
            state("b", x: 300 + step * cos(angle), y: 200 + step * sin(angle), rotation: angle),
        ], sizeOf: size))

        #expect(abs(box.width - 200) < 1e-9 && abs(box.height - 50) < 1e-9, "\(box.width)×\(box.height)")
        #expect(box.rotation == angle)
    }

    /// Sprites turned differently have no one angle; the upright box has to
    /// contain their turned corners, not their upright extents.
    @Test("mixed angles give an upright box around the turned corners")
    func mixedAnglesContainCorners() throws {
        let box = try #require(ClipBounds.around([
            state("a", x: 300, y: 200, rotation: .pi / 2),
            state("b", x: 300, y: 200, rotation: 0),
        ], sizeOf: size))

        // A 100×50 sprite stood on end reaches 50 above and below its centre.
        #expect(box.rotation == 0)
        #expect(abs(box.minY - 150) < 1e-9 && abs(box.maxY - 250) < 1e-9, "\(box.minY)…\(box.maxY)")
        #expect(abs(box.minX - 250) < 1e-9 && abs(box.maxX - 350) < 1e-9)
    }
}
