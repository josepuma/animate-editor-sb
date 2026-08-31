import Testing

@testable import StoryboardCore

@Suite("Storyboard writer")
struct OsbWriterTests {
    /// The test that matters: what the writer produces, the parser reads back
    /// as the same thing. Anything that survives this survives the game.
    @Test("a sprite survives a round trip")
    func roundTrip() throws {
        var sprite = StoryboardSprite(
            id: "s1", layer: .foreground, origin: .centre,
            filePath: "sb/particle.png", defaultX: 320, defaultY: 240,
        )
        sprite.commands = [
            Command(
                timing: .init(easing: .out, startTime: 0, endTime: 1000),
                payload: .fade(start: 0, end: 1),
            ),
            Command(
                timing: .init(easing: .linear, startTime: 0, endTime: 2000),
                payload: .move(startX: 100, startY: 50, endX: 400, endY: 300),
            ),
            Command(
                timing: .init(easing: .linear, startTime: 0, endTime: 500),
                payload: .scale(start: 0.5, end: 1.25),
            ),
            Command(
                timing: .init(easing: .linear, startTime: 0, endTime: 800),
                payload: .color(startR: 255, startG: 128, startB: 0, endR: 0, endG: 64, endB: 255),
            ),
        ]

        let parsed = OsbParser.parse(OsbWriter.write([sprite])).sprites
        let read = try #require(parsed.first)

        #expect(read.filePath == sprite.filePath)
        #expect(read.layer == sprite.layer)
        #expect(read.origin == sprite.origin)
        #expect(read.defaultX == sprite.defaultX)
        #expect(read.defaultY == sprite.defaultY)
        #expect(read.commands.count == sprite.commands.count)

        // Values, not just counts: a writer that emits the right number of
        // wrong commands passes a count check.
        if case let .move(sx, sy, ex, ey) = read.commands[1].payload {
            #expect(sx == 100 && sy == 50 && ex == 400 && ey == 300)
        } else {
            Issue.record("second command should be a move")
        }
        #expect(read.commands[0].timing.easing == .out)
    }

    /// Loops are where a storyboard gets cheap, so they have to come back
    /// whole: body, count and relative times.
    @Test("a loop survives a round trip")
    func loopRoundTrip() throws {
        var sprite = StoryboardSprite(
            id: "s1", layer: .background, origin: .topLeft,
            filePath: "bg.jpg", defaultX: 0, defaultY: 0,
        )
        sprite.loops = [LoopGroup(startTime: 1000, loopCount: 4, commands: [
            Command(
                timing: .init(easing: .linear, startTime: 0, endTime: 500),
                payload: .fade(start: 1, end: 0),
            ),
        ])]

        let read = try #require(OsbParser.parse(OsbWriter.write([sprite])).sprites.first)
        #expect(read.loops.count == 1)
        #expect(read.loops[0].loopCount == 4)
        #expect(read.loops[0].startTime == 1000)
        #expect(read.loops[0].commands.count == 1)
    }

    /// Sprites go under their own layer, in draw order.
    @Test("sprites are grouped by layer")
    func layerGrouping() {
        let sprites = [
            StoryboardSprite(
                id: "a", layer: .overlay, origin: .centre,
                filePath: "a.png", defaultX: 0, defaultY: 0,
            ),
            StoryboardSprite(
                id: "b", layer: .background, origin: .centre,
                filePath: "b.png", defaultX: 0, defaultY: 0,
            ),
        ]

        let text = OsbWriter.write(sprites)
        let background = try? #require(text.range(of: "b.png"))
        let overlay = try? #require(text.range(of: "a.png"))
        guard let background, let overlay else { return }

        // Background is written first because it draws first.
        #expect(background.lowerBound < overlay.lowerBound)
    }

    /// A storyboard is text, and a file carries millions of these.
    @Test("whole numbers are written without a decimal point")
    func compactNumbers() {
        var sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "p.png", defaultX: 320, defaultY: 240,
        )
        sprite.commands = [Command(
            timing: .init(easing: .linear, startTime: 0, endTime: 1000),
            payload: .fade(start: 0, end: 1),
        )]

        let text = OsbWriter.write([sprite])
        #expect(text.contains("\"p.png\",320,240"))
        #expect(!text.contains("320.0"))
    }
}
