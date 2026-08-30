import Foundation
import Testing

@testable import StoryboardCore

// ─── Fixture model ───────────────────────────────────────────────────────────

private struct ResolverGolden: Decodable {
    struct SpriteInfo: Decodable {
        let id: String
        let layer: String
        let origin: String
        let filePath: String
        let defaultX: Double
        let defaultY: Double
        let commandCount: Int
        let loopCount: Int
    }

    struct State: Decodable {
        let spriteId: String
        let x: Double
        let y: Double
        let scaleX: Double
        let scaleY: Double
        let rotation: Double
        let opacity: Double
        let r: Double
        let g: Double
        let b: Double
        let visible: Bool
        let additive: Bool
        let flipH: Bool
        let flipV: Bool
    }

    struct Frame: Decodable {
        let time: Double
        let states: [State]
    }

    struct Case: Decodable {
        let osb: String
        let sprites: [SpriteInfo]
        let frames: [Frame]
    }

    let description: String
    let cases: [String: Case]
}

private func loadGolden() throws -> ResolverGolden {
    let url = try #require(
        Bundle.module.url(forResource: "resolver-golden", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "resolver-golden", withExtension: "json"),
        "resolver-golden.json fixture is missing from the test bundle",
    )
    return try JSONDecoder().decode(ResolverGolden.self, from: Data(contentsOf: url))
}

// ─── Tests ───────────────────────────────────────────────────────────────────

@Suite("StoryboardResolver — parity with the TypeScript engine")
struct ResolverGoldenTests {
    /// Tolerance for cross-language float comparison. Both languages use
    /// IEEE-754 binary64; differences come only from libm.
    static let tolerance = 1e-9

    @Test("every case resolves identically to the TypeScript engine")
    func allCasesMatchGolden() throws {
        let golden = try loadGolden()
        #expect(!golden.cases.isEmpty, "fixture contains no cases")

        for (name, testCase) in golden.cases.sorted(by: { $0.key < $1.key }) {
            let storyboard = OsbParser.parse(testCase.osb)
            let prepared = StoryboardResolver.prepare(storyboard.sprites)

            for frame in testCase.frames {
                let actual = StoryboardResolver.resolve(prepared, at: frame.time)

                #expect(
                    actual.count == frame.states.count,
                    "[\(name)] t=\(frame.time): got \(actual.count) states, expected \(frame.states.count)",
                )
                guard actual.count == frame.states.count else { continue }

                for (state, want) in zip(actual, frame.states) {
                    let label = "[\(name)] t=\(frame.time) sprite=\(want.spriteId)"

                    #expect(state.spriteId == want.spriteId, "\(label): sprite id mismatch")
                    expectClose(state.x, want.x, "\(label) x")
                    expectClose(state.y, want.y, "\(label) y")
                    expectClose(state.scaleX, want.scaleX, "\(label) scaleX")
                    expectClose(state.scaleY, want.scaleY, "\(label) scaleY")
                    expectClose(state.rotation, want.rotation, "\(label) rotation")
                    expectClose(state.opacity, want.opacity, "\(label) opacity")
                    expectClose(state.r, want.r, "\(label) r")
                    expectClose(state.g, want.g, "\(label) g")
                    expectClose(state.b, want.b, "\(label) b")
                    #expect(state.visible == want.visible, "\(label): visible mismatch")
                    #expect(state.additive == want.additive, "\(label): additive mismatch")
                    #expect(state.flipH == want.flipH, "\(label): flipH mismatch")
                    #expect(state.flipV == want.flipV, "\(label): flipV mismatch")
                }
            }
        }
    }

    @Test("the parser produces the same sprites as the TypeScript parser")
    func parsedSpritesMatchGolden() throws {
        let golden = try loadGolden()

        for (name, testCase) in golden.cases.sorted(by: { $0.key < $1.key }) {
            let storyboard = OsbParser.parse(testCase.osb)

            #expect(
                storyboard.sprites.count == testCase.sprites.count,
                "[\(name)]: got \(storyboard.sprites.count) sprites, expected \(testCase.sprites.count)",
            )
            guard storyboard.sprites.count == testCase.sprites.count else { continue }

            for (sprite, want) in zip(storyboard.sprites, testCase.sprites) {
                #expect(sprite.id == want.id, "[\(name)]: sprite id mismatch")
                #expect(sprite.filePath == want.filePath, "[\(name)] \(want.id): file path mismatch")
                #expect(sprite.defaultX == want.defaultX, "[\(name)] \(want.id): defaultX mismatch")
                #expect(sprite.defaultY == want.defaultY, "[\(name)] \(want.id): defaultY mismatch")
                #expect(
                    sprite.commands.count == want.commandCount,
                    "[\(name)] \(want.id): got \(sprite.commands.count) commands, expected \(want.commandCount)",
                )
                #expect(
                    sprite.loops.count == want.loopCount,
                    "[\(name)] \(want.id): got \(sprite.loops.count) loops, expected \(want.loopCount)",
                )
            }
        }
    }

    private func expectClose(
        _ actual: Double,
        _ expected: Double,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        let delta = abs(actual - expected)
        #expect(
            delta <= Self.tolerance,
            "\(label): got \(actual), expected \(expected), delta \(delta)",
            sourceLocation: sourceLocation,
        )
    }
}

// ─── Behaviour tests independent of the fixture ──────────────────────────────

@Suite("StoryboardResolver — behaviour")
struct ResolverBehaviourTests {
    private func sprite(_ osb: String) -> [PreparedSprite] {
        StoryboardResolver.prepare(OsbParser.parse(osb).sprites)
    }

    @Test("sprites with no commands are dropped")
    func dropsSpritesWithoutCommands() {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        """)
        #expect(prepared.isEmpty)
    }

    @Test("parameter commands do not define the active window")
    func parametersDoNotDefineLifetime() throws {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _P,0,0,0,A
        _F,0,1000,2000,0,1
        """)

        let first = try #require(prepared.first)
        #expect(first.activeStart == 1000)
        #expect(first.activeEnd == 2000)
    }

    @Test("a sprite outside its active window resolves to nothing")
    func outsideActiveWindowResolvesEmpty() {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,1000,2000,0,1
        """)

        #expect(StoryboardResolver.resolve(prepared, at: 999).isEmpty)
        #expect(StoryboardResolver.resolve(prepared, at: 2001).isEmpty)
        #expect(StoryboardResolver.resolve(prepared, at: 1500).count == 1)
    }

    @Test("visibility follows opacity")
    func visibilityFollowsOpacity() throws {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,0,1000,0,1
        """)

        #expect(StoryboardResolver.resolve(prepared, at: 0).first?.visible == false)
        #expect(StoryboardResolver.resolve(prepared, at: 1000).first?.visible == true)
    }

    @Test("a zero-length parameter lasts the sprite's whole lifetime")
    func zeroLengthParameterLastsLifetime() {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,0,1000,1,1
        _P,0,0,0,A
        """)

        for time in [0.0, 500.0, 1000.0] {
            #expect(
                StoryboardResolver.resolve(prepared, at: time).first?.additive == true,
                "expected additive at t=\(time)",
            )
        }
    }

    @Test("an empty loop body is ignored")
    func emptyLoopIsIgnored() throws {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,0,1000,0,1
        _L,2000,4
        """)

        let first = try #require(prepared.first)
        #expect(first.activeEnd == 1000)
    }

    @Test("resolving into a reused buffer clears previous results")
    func resolveIntoReusesBuffer() {
        let prepared = sprite("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,0,1000,0,1
        """)

        var buffer: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: 500, into: &buffer)
        #expect(buffer.count == 1)

        StoryboardResolver.resolve(prepared, at: 5000, into: &buffer)
        #expect(buffer.isEmpty)
    }

    @Test("layer, origin and file path survive preparation")
    func preparationKeepsRenderMetadata() throws {
        let prepared = sprite("""
        [Events]
        Sprite,Overlay,BottomRight,"sb/x.png",100,200
        _F,0,0,1000,0,1
        """)

        let first = try #require(prepared.first)
        #expect(first.layer == .overlay)
        #expect(first.origin == .bottomRight)
        #expect(first.filePath == "sb/x.png")
        #expect(first.defaultX == 100)
        #expect(first.defaultY == 200)
    }
}

// ─── Duration ────────────────────────────────────────────────────────────────

@Suite("StoryboardResolver — duration")
struct ResolverDurationTests {
    private func prepared(_ osb: String) -> [PreparedSprite] {
        StoryboardResolver.prepare(OsbParser.parse(osb).sprites)
    }

    @Test("an empty storyboard has a non-zero duration")
    func emptyStoryboard() {
        #expect(StoryboardResolver.duration(of: []) == 1)
    }

    @Test("duration is the last sprite's end time")
    func lastSpriteEndTime() {
        let sprites = prepared("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,0,1000,0,1
        Sprite,Foreground,Centre,"b.png",320,240
        _F,0,0,5000,0,1
        """)

        #expect(StoryboardResolver.duration(of: sprites) == 5000)
    }

    @Test("a single runaway sprite does not stretch the duration")
    func ignoresRunawaySprite() {
        // One sprite fading out at the twelve-hour mark would otherwise leave
        // the transport scrubbing across mostly empty time.
        var lines = ["[Events]"]
        for index in 0..<40 {
            lines.append(#"Sprite,Foreground,Centre,"s\#(index).png",320,240"#)
            lines.append("_F,0,0,10000,0,1")
        }
        lines.append(#"Sprite,Foreground,Centre,"runaway.png",320,240"#)
        lines.append("_F,0,0,43200000,0,1")

        let sprites = prepared(lines.joined(separator: "\n"))
        let duration = StoryboardResolver.duration(of: sprites)

        #expect(duration == 10000, "expected the bulk of the storyboard, not the outlier")
    }

    @Test("a sprite ending slightly later is kept")
    func keepsNearbyTail() {
        // A tail within a minute of the rest is real content, not an outlier.
        var lines = ["[Events]"]
        for index in 0..<40 {
            lines.append(#"Sprite,Foreground,Centre,"s\#(index).png",320,240"#)
            lines.append("_F,0,0,10000,0,1")
        }
        lines.append(#"Sprite,Foreground,Centre,"tail.png",320,240"#)
        lines.append("_F,0,0,40000,0,1")

        let sprites = prepared(lines.joined(separator: "\n"))
        #expect(StoryboardResolver.duration(of: sprites) == 40000)
    }

    // ─── Time range ──────────────────────────────────────────────────────────

    @Test("the range opens where the storyboard does, even before zero")
    func rangeStartsEarly() {
        let sprites = prepared("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,-2000,1000,0,1
        """)

        #expect(StoryboardResolver.timeRange(of: sprites).lowerBound == -2000)
    }

    @Test("the range never opens after zero")
    func rangeNeverStartsLate() {
        // A storyboard beginning at 0:30 still has a timeline that starts at
        // the track's own beginning; the empty stretch before it is where the
        // music plays.
        let sprites = prepared("""
        [Events]
        Sprite,Foreground,Centre,"a.png",320,240
        _F,0,30000,31000,0,1
        """)

        #expect(StoryboardResolver.timeRange(of: sprites).lowerBound == 0)
    }

    @Test("the range reaches the last command, unlike the duration")
    func rangeKeepsTheOutlier() {
        // `duration` drops a trailing outlier so playback does not run on in
        // silence. The timeline cannot: it draws that sprite's clip, and a span
        // ending before the clip leaves it hanging past the end of the track.
        var lines = ["[Events]"]
        for index in 0..<40 {
            lines.append(#"Sprite,Foreground,Centre,"s\#(index).png",320,240"#)
            lines.append("_F,0,0,10000,0,1")
        }
        lines.append(#"Sprite,Foreground,Centre,"runaway.png",320,240"#)
        lines.append("_F,0,0,43200000,0,1")

        let sprites = prepared(lines.joined(separator: "\n"))

        #expect(StoryboardResolver.duration(of: sprites) == 10000)
        #expect(StoryboardResolver.timeRange(of: sprites).upperBound == 43_200_000)
    }

    @Test("an empty storyboard still has a span")
    func emptyRangeHasWidth() {
        // A zero-width range would divide by nothing everywhere it is used.
        let range = StoryboardResolver.timeRange(of: [])
        #expect(range.upperBound > range.lowerBound)
    }
}
