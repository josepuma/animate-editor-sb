import Foundation
import Testing

@testable import StoryboardCore

/// Finding a clip on the timeline to select what is plainly visible on the
/// canvas is a search the picture already answered.
@Suite("Canvas hit test")
struct CanvasHitTestTests {
    private func candidate(
        _ id: String,
        x: Double, y: Double,
        width: Double = 100, height: Double = 100,
        rotation: Double = 0,
        opacity: Double = 1,
        origin: Origin = .centre,
    ) -> CanvasHitTest.Candidate {
        CanvasHitTest.Candidate(
            state: SpriteRenderState(spriteId: id, x: x, y: y, rotation: rotation, opacity: opacity),
            width: width,
            height: height,
            origin: origin,
        )
    }

    /// Every sprite here belongs to the clip named before its slash.
    private func owner(_ spriteID: String) -> String? {
        spriteID.split(separator: "/").first.map(String.init)
    }

    @Test("a point inside a sprite finds its clip")
    func findsClip() {
        let hit = CanvasHitTest.clip(
            at: (x: 320, y: 240),
            in: [candidate("a/0", x: 300, y: 220)],
            owner: owner,
        )
        #expect(hit == "a")
    }

    @Test("a point outside every sprite finds nothing")
    func missesEmptySpace() {
        let hit = CanvasHitTest.clip(
            at: (x: 500, y: 400),
            in: [candidate("a/0", x: 300, y: 220)],
            owner: owner,
        )
        #expect(hit == nil)
    }

    /// Candidates come in draw order, so the last one is drawn on top — and on
    /// top is what the pointer is over.
    @Test("the sprite drawn on top wins")
    func topmostWins() {
        let hit = CanvasHitTest.clip(
            at: (x: 300, y: 220),
            in: [candidate("back/0", x: 300, y: 220), candidate("front/0", x: 310, y: 230)],
            owner: owner,
        )
        #expect(hit == "front")
    }

    /// A locked lane, a hidden one, or a sprite from the imported storyboard
    /// has no owner the canvas may select — the click goes to what is behind.
    @Test("a sprite with no selectable owner is clicked through")
    func ownerlessClicksThrough() {
        let hit = CanvasHitTest.clip(
            at: (x: 300, y: 220),
            in: [candidate("back/0", x: 300, y: 220), candidate("locked/0", x: 300, y: 220)],
            owner: { $0.hasPrefix("locked") ? nil : owner($0) },
        )
        #expect(hit == "back")
    }

    /// Faded out it is not on screen, whatever its box says.
    @Test("an invisible sprite is not hit")
    func invisibleIsMissed() {
        let hit = CanvasHitTest.clip(
            at: (x: 300, y: 220),
            in: [candidate("ghost/0", x: 300, y: 220, opacity: 0)],
            owner: owner,
        )
        #expect(hit == nil)
    }

    /// osu! hangs the image off its position by the origin. A `TopLeft`
    /// sprite is drawn below and to the right of where it sits.
    @Test("the origin decides where the sprite is")
    func respectsOrigin() {
        let sprites = [candidate("a/0", x: 100, y: 100, width: 50, height: 50, origin: .topLeft)]
        #expect(CanvasHitTest.clip(at: (x: 120, y: 120), in: sprites, owner: owner) == "a")
        #expect(CanvasHitTest.clip(at: (x: 90, y: 90), in: sprites, owner: owner) == nil)
    }

    /// A long bar turned a quarter stands upright: the hit has to follow the
    /// turn, not the upright box it came from.
    @Test("a turned sprite is hit where it is drawn")
    func followsRotation() {
        let sprites = [candidate("bar/0", x: 300, y: 200, width: 200, height: 20, rotation: .pi / 2)]
        #expect(CanvasHitTest.clip(at: (x: 300, y: 280), in: sprites, owner: owner) == "bar")
        #expect(CanvasHitTest.clip(at: (x: 380, y: 200), in: sprites, owner: owner) == nil)
    }

    /// A quarter turn looks the same either way round; thirty degrees does
    /// not. Clockwise on screen, because y grows downwards.
    @Test("the turn goes the way the sprite turns")
    func rotationSense() {
        let angle = Double.pi / 6
        let sprites = [candidate("bar/0", x: 300, y: 200, width: 200, height: 20, rotation: angle)]
        let along = (x: 300 + 80 * cos(angle), y: 200 + 80 * sin(angle))
        let mirrored = (x: 300 + 80 * cos(angle), y: 200 - 80 * sin(angle))
        #expect(CanvasHitTest.clip(at: along, in: sprites, owner: owner) == "bar")
        #expect(CanvasHitTest.clip(at: mirrored, in: sprites, owner: owner) == nil)
    }

    /// Scale is part of what is drawn.
    @Test("a scaled sprite is hit at its drawn size")
    func followsScale() {
        var big = candidate("a/0", x: 300, y: 200, width: 100, height: 100)
        big.state.scaleX = 3
        big.state.scaleY = 3
        #expect(CanvasHitTest.clip(at: (x: 440, y: 200), in: [big], owner: owner) == "a")
    }
}
