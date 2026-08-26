import Testing

@testable import StoryboardRendering

@Suite("ShelfPacker")
struct ShelfPackerTests {
    @Test("places the first sprite at the page origin")
    func firstSpriteAtOrigin() throws {
        var packer = ShelfPacker(pageSize: 1024)
        let placed2616 = packer.place(width: 64, height: 64)
        let slot = try #require(placed2616)

        #expect(slot.page == 0)
        #expect(slot.x == 0)
        #expect(slot.y == 0)
        #expect(packer.pageCount == 1)
    }

    @Test("lays sprites along a shelf before starting a new one")
    func fillsShelfLeftToRight() throws {
        var packer = ShelfPacker(pageSize: 1024)

        let placed7138 = packer.place(width: 400, height: 100)
        let first = try #require(placed7138)
        let placed464 = packer.place(width: 400, height: 100)
        let second = try #require(placed464)

        #expect(first.y == second.y, "both should share the first shelf")
        #expect(second.x == 400)
    }

    @Test("starts a new shelf when the current one is full")
    func wrapsToNextShelf() throws {
        var packer = ShelfPacker(pageSize: 1024)

        let placed1614 = packer.place(width: 600, height: 100)
        let first = try #require(placed1614)
        let placed3956 = packer.place(width: 600, height: 100)
        let second = try #require(placed3956)

        #expect(second.x == 0, "should wrap to the start of a new shelf")
        #expect(second.y == 100, "new shelf sits below the tallest of the last")
        #expect(first.page == second.page)
    }

    @Test("shelf height follows its tallest sprite")
    func shelfHeightUsesTallest() throws {
        var packer = ShelfPacker(pageSize: 1024)

        let placed3193 = packer.place(width: 300, height: 50)
        _ = try #require(placed3193)
        let placed7707 = packer.place(width: 300, height: 200)
        _ = try #require(placed7707)
        let placed2 = packer.place(width: 600, height: 10)
        _ = try #require(placed2)  // wraps

        let placed3290 = packer.place(width: 10, height: 10)
        let wrapped = try #require(placed3290)
        #expect(wrapped.y >= 200, "must clear the 200-tall sprite above")
    }

    @Test("opens a new page when the current one is full")
    func opensNewPage() throws {
        var packer = ShelfPacker(pageSize: 256)

        // Four 256×64 shelves fill the page exactly; the fifth needs a new one.
        for _ in 0..<4 {
            let placed5679 = packer.place(width: 256, height: 64)
            _ = try #require(placed5679)
        }
        let placed1990 = packer.place(width: 256, height: 64)
        let overflow = try #require(placed1990)

        #expect(overflow.page == 1)
        #expect(overflow.x == 0)
        #expect(overflow.y == 0)
        #expect(packer.pageCount == 2)
    }

    @Test("sprites larger than a page are rejected rather than cropped")
    func oversizedSpriteIsRejected() {
        var packer = ShelfPacker(pageSize: 512)

        // Cropping a sprite while still reporting its full size stretches the
        // image across its quad, so the packer refuses instead.
        #expect(packer.place(width: 4096, height: 100) == nil)
        #expect(packer.place(width: 100, height: 4096) == nil)
        #expect(packer.place(width: 513, height: 513) == nil)
    }

    @Test("a sprite exactly the size of a page still fits")
    func exactPageSizeFits() throws {
        var packer = ShelfPacker(pageSize: 512)
        let placed5389 = packer.place(width: 512, height: 512)
        let slot = try #require(placed5389)

        #expect(slot.x == 0)
        #expect(slot.y == 0)
    }

    @Test("rejecting a sprite does not disturb the packing state")
    func rejectionLeavesStateIntact() throws {
        var packer = ShelfPacker(pageSize: 512)

        let placed4518 = packer.place(width: 100, height: 100)
        let before = try #require(placed4518)
        #expect(packer.place(width: 9999, height: 9999) == nil)
        let placed5331 = packer.place(width: 100, height: 100)
        let after = try #require(placed5331)

        #expect(after.page == before.page)
        #expect(after.x == before.x + 100, "the rejected sprite must not consume space")
    }

    @Test("slots within a page never overlap")
    func slotsDoNotOverlap() throws {
        var packer = ShelfPacker(pageSize: 512)
        let sizes = [(100, 80), (150, 80), (200, 80), (120, 60), (300, 60), (90, 40)]

        var placed: [(page: Int, x: Int, y: Int, width: Int, height: Int)] = []
        for (width, height) in sizes {
            let placed3377 = packer.place(width: width, height: height)
            let slot = try #require(placed3377)
            placed.append((slot.page, slot.x, slot.y, width, height))
        }

        for (index, lhs) in placed.enumerated() {
            for rhs in placed[(index + 1)...] where lhs.page == rhs.page {
                let separated =
                    lhs.x + lhs.width <= rhs.x
                    || rhs.x + rhs.width <= lhs.x
                    || lhs.y + lhs.height <= rhs.y
                    || rhs.y + rhs.height <= lhs.y
                #expect(separated, "slots \(lhs) and \(rhs) overlap")
            }
        }
    }

    @Test("padded slots leave a gap between neighbouring sprites")
    func paddingSeparatesNeighbours() throws {
        // The atlas reserves `TextureAtlas.padding` on every side by inflating
        // each sprite's footprint before packing. Without that gap, linear
        // filtering samples across sprite boundaries and every sprite renders
        // with a border of its neighbour.
        var packer = ShelfPacker(pageSize: 1024)
        let padding = TextureAtlas.padding
        let spriteWidth = 100

        let placed1822 = packer.place(width: spriteWidth + padding * 2, height: 64 + padding * 2)
        let first = try #require(placed1822)
        let placed2870 = packer.place(width: spriteWidth + padding * 2, height: 64 + padding * 2)
        let second = try #require(placed2870)

        let firstPixelsEnd = first.x + padding + spriteWidth
        let secondPixelsStart = second.x + padding

        #expect(
            secondPixelsStart - firstPixelsEnd >= padding * 2,
            "expected at least \(padding * 2) texels between sprite pixels",
        )
    }

    @Test("every slot fits its sprite entirely inside the page")
    func slotsStayInBounds() throws {
        let pageSize = 512
        var packer = ShelfPacker(pageSize: pageSize)

        for index in 0..<40 {
            let width = 40 + (index * 17) % 200
            let height = 30 + (index * 11) % 120
            let placed3377 = packer.place(width: width, height: height)
            let slot = try #require(placed3377)

            #expect(slot.x >= 0)
            #expect(slot.y >= 0)
            // The full sprite must fit: a slot that leaves part of it past the
            // page edge is what produced stretched images.
            #expect(slot.x + width <= pageSize)
            #expect(slot.y + height <= pageSize)
        }
    }

    @Test("a page-wide sprite fits with the atlas gutter applied")
    func pageWideSpriteFitsWithPadding() throws {
        // A 1920×1080 background is the common worst case; it must survive
        // the padding the atlas adds before packing.
        var packer = ShelfPacker(pageSize: TextureAtlas.pageSize)
        let padding = TextureAtlas.padding

        let placed = packer.place(width: 1920 + padding * 2, height: 1080 + padding * 2)
        let slot = try #require(placed)
        #expect(slot.x + padding + 1920 <= TextureAtlas.pageSize)
        #expect(slot.y + padding + 1080 <= TextureAtlas.pageSize)
    }
}
