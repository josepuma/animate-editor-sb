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

    /// A box that ignored rotation would cut the corners off a spinning sprite
    /// — the box has to hold it at every angle, not only at zero.
    @Test("a rotated sprite is contained at any angle")
    func rotationExpandsTheBox() throws {
        let flat = try #require(ClipBounds.around([state("a", x: 320, y: 240)], sizeOf: size))
        let turned = try #require(ClipBounds.around(
            [state("a", x: 320, y: 240, rotation: .pi / 2)], sizeOf: size,
        ))

        // Turned a quarter, the 100×50 sprite reads as 50×100.
        #expect(abs(turned.width - flat.height) < 0.001)
        #expect(abs(turned.height - flat.width) < 0.001)
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
