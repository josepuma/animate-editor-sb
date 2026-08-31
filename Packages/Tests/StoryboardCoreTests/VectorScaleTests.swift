import Foundation
import Testing

@testable import StoryboardCore

@Suite("Per-axis scale")
struct VectorScaleTests {
    private func commands(x: Double, y: Double) -> [Command] {
        TransformCommands.buildScale(
            x: KeyframeTrack(), y: KeyframeTrack(),
            restingX: x, restingY: y, duration: 1000,
        )
    }

    /// The distinction the whole feature rests on: a stretch needs `_V`,
    /// and uniform scaling must not pay for two numbers it does not use.
    @Test("uniform scaling stays a scale command")
    func uniformUsesScale() {
        #expect(commands(x: 2, y: 2).first?.kind == .scale)
    }

    @Test("differing axes become a vector scale")
    func stretchUsesVectorScale() throws {
        let command = try #require(commands(x: 2, y: 0.5).first)
        #expect(command.kind == .vectorScale)

        if case let .vectorScale(sx, sy, _, _) = command.payload {
            #expect(sx == 2)
            #expect(sy == 0.5)
        } else {
            Issue.record("expected a vector scale")
        }
    }

    /// Setting one field is how "make it bigger" arrives, and it must not reach
    /// the file as a stretch.
    @Test("one axis set alone scales uniformly")
    func oneAxisMirrorsTheOther() {
        #expect(commands(x: 3, y: 1).first?.kind == .scale)
        #expect(commands(x: 1, y: 3).first?.kind == .scale)
    }

    @Test("both at the default write nothing")
    func defaultWritesNothing() {
        #expect(commands(x: 1, y: 1).isEmpty)
    }

    /// Animating one axis while the other rests is still uniform — the same
    /// rule, applied over time.
    @Test("animating one axis alone stays uniform")
    func animatedSingleAxisIsUniform() {
        let track = KeyframeTrack([
            Keyframe(time: 0, value: 1),
            Keyframe(time: 1000, value: 2),
        ])
        let built = TransformCommands.buildScale(
            x: track, y: KeyframeTrack(),
            restingX: 1, restingY: 1, duration: 1000,
        )

        #expect(built.allSatisfy { $0.kind == .scale })
        #expect(!built.isEmpty)
    }

    /// Two animated axes share their command, so a key on either one has to be
    /// a boundary for both — or the other's curve is lost inside a segment.
    @Test("a key on either axis cuts the command")
    func keysOnEitherAxisCut() {
        let x = KeyframeTrack([
            Keyframe(time: 0, value: 1),
            Keyframe(time: 1000, value: 2),
        ])
        let y = KeyframeTrack([
            Keyframe(time: 0, value: 1),
            Keyframe(time: 500, value: 3),
            Keyframe(time: 1000, value: 1),
        ])

        let built = TransformCommands.buildScale(
            x: x, y: y, restingX: 1, restingY: 1, duration: 1000,
        )

        // Boundaries at 0, 500 and 1000 — two segments.
        #expect(built.count == 2)
        #expect(built.allSatisfy { $0.kind == .vectorScale })
    }

    /// Round-tripped, because a command the parser cannot read back is a
    /// command the game will not draw either.
    @Test("a stretch survives a round trip")
    func stretchRoundTrips() throws {
        var sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "a.png", defaultX: 320, defaultY: 240,
        )
        sprite.commands = commands(x: 2, y: 0.5)

        let read = try #require(OsbParser.parse(OsbWriter.write([sprite])).sprites.first)
        if case let .vectorScale(sx, sy, _, _) = read.commands[0].payload {
            #expect(sx == 2)
            #expect(sy == 0.5)
        } else {
            Issue.record("vector scale did not survive")
        }
    }
}

@Suite("Scale migration")
struct ScaleMigrationTests {
    /// A project saved before scale had two axes must not open with its
    /// scaling quietly gone: nothing reads the old key any more.
    @Test("a legacy scale becomes both axes")
    func legacyScaleMigrates() throws {
        let json = """
        {"tracks":{},"values":{"scale":2.5,"x":100}}
        """
        let transform = try JSONDecoder().decode(Transform.self, from: Data(json.utf8))

        #expect(transform[value: .scaleX] == 2.5)
        #expect(transform[value: .scaleY] == 2.5)
        #expect(transform[value: .x] == 100)
    }

    @Test("a legacy animated scale becomes both axes")
    func legacyTrackMigrates() throws {
        let json = """
        {"tracks":{"scale":{"isEnabled":true,"keyframes":[
        {"id":"k1","time":0,"value":1,"easing":0},
        {"id":"k2","time":1000,"value":3,"easing":0}]}},"values":{}}
        """
        let transform = try JSONDecoder().decode(Transform.self, from: Data(json.utf8))

        #expect(transform[.scaleX].keyframes.count == 2)
        #expect(transform[.scaleY].keyframes.count == 2)
    }
}
