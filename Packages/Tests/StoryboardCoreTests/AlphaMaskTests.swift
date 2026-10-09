import Foundation
import Testing

@testable import StoryboardCore

/// What you see is what you pick: a sprite's transparent pixels are not a
/// wall in front of what shows through them.
@Suite("Alpha mask")
struct AlphaMaskTests {
    @Test("a small image keeps its size")
    func smallKeepsSize() {
        #expect(AlphaMask.size(width: 4, height: 2) == (4, 2))
    }

    @Test("a large image shrinks to the longest side, keeping its shape")
    func largeShrinks() {
        #expect(AlphaMask.size(width: 256, height: 128) == (AlphaMask.maximumSide, AlphaMask.maximumSide / 2))
    }

    @Test("a sliver never shrinks to nothing")
    func sliverKeepsAPixel() {
        #expect(AlphaMask.size(width: 2048, height: 1) == (AlphaMask.maximumSide, 1))
    }

    @Test("rows run from the top, the way the texture does")
    func rowsFromTop() {
        let mask = AlphaMask(width: 2, height: 2, alpha: [255, 255, 0, 0])
        #expect(mask.alpha(u: 0.5, v: 0.1) == 1)
        #expect(mask.alpha(u: 0.5, v: 0.9) == 0)
    }

    @Test("off the image reads clear")
    func offImage() {
        let mask = AlphaMask(width: 1, height: 1, alpha: [255])
        #expect(mask.alpha(u: 1.2, v: 0.5) == 0)
        #expect(mask.alpha(u: 0.5, v: -0.1) == 0)
    }
}

@Suite("Canvas hit test by alpha")
struct CanvasHitAlphaTests {
    /// A 2×1 mask: the left half opaque, the right half clear.
    private let leftHalf = AlphaMask(width: 2, height: 1, alpha: [255, 0])

    private func candidate(
        _ id: String,
        x: Double = 300, y: Double = 200,
        width: Double = 100, height: Double = 100,
        rotation: Double = 0,
        opacity: Double = 1,
        flipH: Bool = false,
        mask: AlphaMask?,
    ) -> CanvasHitTest.Candidate {
        CanvasHitTest.Candidate(
            state: SpriteRenderState(
                spriteId: id, x: x, y: y, rotation: rotation, opacity: opacity, flipH: flipH,
            ),
            width: width,
            height: height,
            origin: .centre,
            mask: mask,
        )
    }

    private func owner(_ spriteID: String) -> String? {
        spriteID.split(separator: "/").first.map(String.init)
    }

    /// The reported bug: a glow drawn over everything caught every pointer.
    @Test("a clear part of a sprite on top lets the one behind through")
    func clearPartPassesThrough() {
        let sprites = [
            candidate("back/0", mask: nil),
            candidate("front/0", mask: leftHalf),
        ]
        // Right of centre: the front sprite is clear there.
        #expect(CanvasHitTest.clip(at: (x: 330, y: 200), in: sprites, owner: owner) == "back")
        // Left of centre: it is opaque, and on top.
        #expect(CanvasHitTest.clip(at: (x: 270, y: 200), in: sprites, owner: owner) == "front")
    }

    /// Opaque pixels at a tenth of a percent are not something anyone sees.
    @Test("a sprite faded almost out is clicked through")
    func fadedPassesThrough() {
        let sprites = [
            candidate("back/0", mask: nil),
            candidate("front/0", opacity: 0.03, mask: AlphaMask(width: 1, height: 1, alpha: [255])),
        ]
        #expect(CanvasHitTest.clip(at: (x: 300, y: 200), in: sprites, owner: owner) == "back")
    }

    /// osu! flips a sprite in place: its opaque half moves to the other side.
    @Test("a flipped sprite is opaque where it is drawn opaque")
    func followsFlip() {
        let sprites = [candidate("a/0", flipH: true, mask: leftHalf)]
        #expect(CanvasHitTest.clip(at: (x: 330, y: 200), in: sprites, owner: owner) == "a")
        #expect(CanvasHitTest.clip(at: (x: 270, y: 200), in: sprites, owner: owner) == nil)
    }

    /// A `TopLeft` sprite hangs right and down from its position, and its
    /// opaque half with it.
    @Test("the origin moves where the opaque part is")
    func followsOrigin() {
        let sprite = CanvasHitTest.Candidate(
            state: SpriteRenderState(spriteId: "a/0", x: 100, y: 100),
            width: 100, height: 100, origin: .topLeft, mask: leftHalf,
        )
        #expect(CanvasHitTest.clip(at: (x: 120, y: 150), in: [sprite], owner: owner) == "a")
        #expect(CanvasHitTest.clip(at: (x: 180, y: 150), in: [sprite], owner: owner) == nil)
        #expect(CanvasHitTest.clip(at: (x: 80, y: 150), in: [sprite], owner: owner) == nil)
    }

    /// Turned a quarter clockwise, the image's left side points up.
    @Test("a turned sprite is opaque where it is drawn opaque")
    func followsRotation() {
        let sprites = [candidate("a/0", width: 100, height: 20, rotation: .pi / 2, mask: leftHalf)]
        #expect(CanvasHitTest.clip(at: (x: 300, y: 170), in: sprites, owner: owner) == "a")
        #expect(CanvasHitTest.clip(at: (x: 300, y: 230), in: sprites, owner: owner) == nil)
    }
}
