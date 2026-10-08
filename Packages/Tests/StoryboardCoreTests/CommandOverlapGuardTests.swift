import Foundation
import StoryboardTestSupport
import Testing

@testable import StoryboardCore

/// The shared overlap guard has to be able to fail, or every sweep built on it
/// reports "clean" regardless.
@Suite("Command overlap guard")
struct CommandOverlapGuardTests {
    private func sprite(_ commands: [Command], loops: [LoopGroup] = []) -> StoryboardSprite {
        var sprite = StoryboardSprite(
            id: "probe", layer: .foreground, origin: .centre, filePath: "x.png", defaultX: 0, defaultY: 0,
        )
        sprite.commands = commands
        sprite.loops = loops
        return sprite
    }

    private func fade(_ start: Double, _ end: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .fade(start: 0, end: 1))
    }

    @Test("two fades overlapping are reported, touching ones are not")
    func overlap() {
        #expect(CommandOverlapGuard.violations(sprite([fade(0, 300), fade(200, 500)])).count == 1)
        #expect(CommandOverlapGuard.violations(sprite([fade(0, 300), fade(300, 500)])).isEmpty)
    }

    @Test("an overlap inside a loop body is reported")
    func insideLoop() {
        let loop = LoopGroup(startTime: 0, loopCount: 3, commands: [fade(0, 300), fade(100, 400)])
        #expect(CommandOverlapGuard.violations(sprite([], loops: [loop])).count == 1)
    }

    @Test("a loop body is its own timeline, not the sprite's")
    func loopIsSeparate() {
        // Same numbers as the sprite's own fade, but relative to an iteration:
        // osu! never plays the two against each other.
        let loop = LoopGroup(startTime: 5000, loopCount: 3, commands: [fade(0, 300)])
        #expect(CommandOverlapGuard.violations(sprite([fade(0, 300)], loops: [loop])).isEmpty)
    }

    @Test("_M beside _MX is reported even apart in time")
    func mixedMoves() {
        let commands = [
            Command(easing: .linear, startTime: 0, endTime: 100, payload: .move(startX: 0, startY: 0, endX: 1, endY: 1)),
            Command(easing: .linear, startTime: 900, endTime: 1000, payload: .moveX(start: 0, end: 5)),
        ]
        #expect(CommandOverlapGuard.violations(sprite(commands)).count == 1)
    }
}
