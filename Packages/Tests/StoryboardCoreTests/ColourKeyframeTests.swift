import Testing

@testable import StoryboardCore

@Suite("Colour keyframes")
struct ColourKeyframeTests {
    private func sprite(_ configure: (inout Transform) -> Void) -> StoryboardSprite {
        var transform = Transform()
        configure(&transform)

        var bare = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "a.png", defaultX: 320, defaultY: 240,
        )
        bare.commands = [Command(
            easing: .linear, startTime: 0, endTime: 3000, payload: .fade(start: 1, end: 1),
        )]
        return GroupTransform.apply(transform, to: [bare], duration: 3000)[0]
    }

    private func colours(_ sprite: StoryboardSprite) -> [Command] {
        sprite.commands.filter { $0.kind == .color }
    }

    @Test("an animated channel reaches the sprite")
    func animatedChannelIsWritten() throws {
        let drawn = sprite {
            $0[.red] = KeyframeTrack([
                Keyframe(time: 0, value: 20),
                Keyframe(time: 3000, value: 240),
            ])
        }

        let command = try #require(colours(drawn).first)
        if case let .color(startR, _, _, endR, _, _) = command.payload {
            #expect(startR == 20)
            #expect(endR == 240)
        } else {
            Issue.record("expected a colour command")
        }
    }

    /// The three channels share one command, so a key on any of them has to be
    /// a boundary for all three — the same rule scale and position follow.
    @Test("a key on one channel cuts the command for all three")
    func keysOnAnyChannelCut() {
        let drawn = sprite {
            $0[.red] = KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 3000, value: 255),
            ])
            $0[.blue] = KeyframeTrack([
                Keyframe(time: 0, value: 255),
                Keyframe(time: 1500, value: 0),
                Keyframe(time: 3000, value: 255),
            ])
        }

        // Boundaries at 0, 1500 and 3000 — two segments.
        #expect(colours(drawn).count == 2)
    }

    /// A channel left alone holds its resting value across the animation rather
    /// than dropping to zero.
    @Test("an unanimated channel holds its value")
    func unanimatedChannelsHold() throws {
        let drawn = sprite {
            $0[.red] = KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 3000, value: 255),
            ])
        }

        let command = try #require(colours(drawn).first)
        if case let .color(_, startG, startB, _, endG, endB) = command.payload {
            #expect(startG == 255 && startB == 255)
            #expect(endG == 255 && endB == 255)
        } else {
            Issue.record("expected a colour command")
        }
    }

    /// White is what a sprite already draws as, so saying so costs a command
    /// for nothing.
    @Test("plain white writes no command")
    func whiteWritesNothing() {
        #expect(colours(sprite { _ in }).isEmpty)
    }

    /// A colour set but never animated still has to reach the file.
    @Test("a resting colour is written once")
    func restingColourIsWritten() {
        let drawn = sprite { $0[value: .red] = 255; $0[value: .green] = 0; $0[value: .blue] = 0 }

        #expect(colours(drawn).count == 1)
        #expect(colours(drawn)[0].startTime == colours(drawn)[0].endTime)
    }
}
