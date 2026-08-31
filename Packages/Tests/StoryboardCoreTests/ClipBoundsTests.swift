import Foundation
import Testing

@testable import StoryboardCore

@Suite("Clip bounds")
struct ClipBoundsTests {
    private func state(
        _ id: String, x: Double, y: Double,
        scale: Double = 1, rotation: Double = 0, opacity: Double = 1,
    ) -> SpriteRenderState {
        SpriteRenderState(
            spriteId: id, x: x, y: y,
            scaleX: scale, scaleY: scale,
            rotation: rotation, opacity: opacity,
            r: 255, g: 255, b: 255,
            visible: true, additive: false, flipH: false, flipV: false,
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
