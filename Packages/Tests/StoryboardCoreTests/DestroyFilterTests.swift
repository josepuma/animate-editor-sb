import Foundation
import StoryboardTestSupport
import Testing

@testable import StoryboardCore

/// The Destroy filters: Shatter, Slice Glitch, Disintegrate, Spark Trail and
/// Impact Ring. Read back through the resolver that draws them.
@Suite("Destroy filters")
struct DestroyFilterTests {
    private func context(_ filter: FilterDescriptor, _ values: [String: EffectValue] = [:]) -> FilterContext {
        FilterContext(
            descriptor: filter,
            node: FilterNode(id: "f", type: filter.type, values: filter.defaultValues.merging(values) { _, new in new }),
        )
    }

    private func sprite(id: String = "s", end: Double = 3000, moves: [Command] = []) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: "a.png", defaultX: 320, defaultY: 240,
            commands: [Command(easing: .linear, startTime: 0, endTime: end, payload: .fade(start: 1, end: 1))] + moves,
        )
    }

    private func state(_ sprite: StoryboardSprite, _ time: Double) -> SpriteRenderState {
        StoryboardResolver.state(of: StoryboardResolver.prepare([sprite])[0], at: time)
    }

    private func move(_ from: (Double, Double), _ to: (Double, Double), _ start: Double, _ end: Double) -> Command {
        Command(easing: .linear, startTime: start, endTime: end, payload: .move(startX: from.0, startY: from.1, endX: to.0, endY: to.1))
    }

    // MARK: - Tile path

    @Test("a tile path round-trips and clamps its cell")
    func tilePath() throws {
        let path = DerivedSprite.tiled("sb/a.png", columns: 4, rows: 3, index: 5)
        #expect(path == "__derived__/tile4x3-5/sb/a.png")
        #expect(try #require(DerivedSprite.parse(path)).kind == .tile(columns: 4, rows: 3, index: 5))
        #expect(DerivedSprite.tiled("a.png", columns: 2, rows: 2, index: 9) == "__derived__/tile2x2-3/a.png")
    }

    // MARK: - Shatter

    private let shatter: [String: EffectValue] = [
        ShatterFilter.Param.columns: .integer(2), ShatterFilter.Param.rows: .integer(2),
        ShatterFilter.Param.breakAt: .number(1000), ShatterFilter.Param.fly: .number(1000),
        ShatterFilter.Param.gravity: .number(0),
    ]

    @Test("the sprite becomes its pieces, whole until the break")
    func shatterWhole() {
        // Moving through the break, so commands that span it have to be cut.
        let out = ShatterFilter().apply(
            to: [sprite(moves: [move((320, 240), (320, 240), 0, 3000)])],
            in: context(ShatterFilter.descriptor, shatter),
        )
        #expect(out.count == 4)
        #expect(out.flatMap(CommandOverlapGuard.violations).isEmpty)
        #expect(Set(out.map(\.filePath)).count == 4)
        #expect(out.allSatisfy { $0.filePath.hasPrefix("__derived__/tile2x2-") })
        for piece in out {
            let before = state(piece, 500)
            #expect(before.x == 320 && before.y == 240 && before.opacity == 1)
        }
    }

    @Test("after the break each piece flies outward from the middle and fades")
    func shatterFlies() {
        let out = ShatterFilter().apply(to: [sprite()], in: context(ShatterFilter.descriptor, shatter))
        let topLeft = state(out[0], 1500)
        let bottomRight = state(out[3], 1500)
        #expect(topLeft.x < 320 && topLeft.y < 240)
        #expect(bottomRight.x > 320 && bottomRight.y > 240)
        #expect(state(out[0], 2000).opacity < 0.01)
    }

    @Test("a sprite not alive at the break is left whole")
    func shatterMissesTheDead() {
        let out = ShatterFilter().apply(to: [sprite(end: 800)], in: context(ShatterFilter.descriptor, shatter))
        #expect(out.count == 1 && out[0].filePath == "a.png")
    }

    @Test("the clip runs until the last piece is gone")
    func shatterDuration() {
        #expect(ShatterFilter().duration(of: 1500, in: context(ShatterFilter.descriptor, shatter)) == 2000)
        #expect(ShatterFilter().estimatedMultiplier(in: context(ShatterFilter.descriptor, shatter)) == 4)
    }

    // MARK: - Slice Glitch

    @Test("bands jump sideways on their own and snap rather than slide")
    func sliceJumps() {
        let out = SliceGlitchFilter().apply(
            to: [sprite()],
            in: context(SliceGlitchFilter.descriptor, [SliceGlitchFilter.Param.slices: .integer(4), SliceGlitchFilter.Param.chance: .number(0.6)]),
        )
        #expect(out.count == 4)
        #expect(out[0].filePath == "__derived__/tile1x4-0/a.png")
        // Snaps: every move is zero-length.
        #expect(out.allSatisfy { $0.commands.filter(\.isPosition).allSatisfy { $0.startTime == $0.endTime } })
        // Sideways only, within the amount, and the bands disagree somewhere.
        var differ = false
        for time in stride(from: 0.0, through: 3000, by: 125) {
            let xs = out.map { state($0, time).x }
            #expect(out.allSatisfy { state($0, time).y == 240 })
            #expect(xs.allSatisfy { abs($0 - 320) <= 24 })
            if Set(xs).count > 1 { differ = true }
        }
        #expect(differ)
    }

    @Test("no chance, no glitch")
    func sliceInert() {
        let out = SliceGlitchFilter().apply(to: [sprite()], in: context(SliceGlitchFilter.descriptor, [SliceGlitchFilter.Param.chance: .number(0)]))
        #expect(out.count == 1 && out[0].filePath == "a.png")
    }

    // MARK: - Disintegrate

    @Test("motes leave over the end of each life, from around the sprite")
    func disintegrates() {
        let out = DisintegrateFilter().apply(
            to: [sprite(), sprite(id: "b")],
            in: context(DisintegrateFilter.descriptor, [
                DisintegrateFilter.Param.window: .number(500), FilterParticles.Param.count: .number(6),
                DisintegrateFilter.Param.width: .number(40), DisintegrateFilter.Param.height: .number(20),
            ]),
        )
        #expect(out.count == 2 + 12)
        #expect(out[0].filePath == "a.png" && out[1].filePath == "a.png", "the sprites stay")
        for mote in out.dropFirst(2) {
            let birth = mote.commands.map(\.startTime).min()!
            #expect(birth >= 2500 && birth <= 3000)
            #expect(abs(mote.defaultX - 320) <= 20 && abs(mote.defaultY - 240) <= 10)
        }
    }

    @Test("the clip total gives way rather than the clip")
    func disintegrateCap() {
        let many = (0..<200).map { sprite(id: "s\($0)") }
        let out = DisintegrateFilter().apply(to: many, in: context(DisintegrateFilter.descriptor, [FilterParticles.Param.count: .number(24)]))
        #expect(out.count - 200 <= FilterParticles.maximumTotal)
    }

    // MARK: - Spark Trail

    @Test("sparks fall along the path while it moves, thrown back against it")
    func sparkTrail() {
        let moving = sprite(moves: [move((0, 240), (600, 240), 0, 1000)])
        let out = SparkTrailFilter().apply(
            to: [moving],
            in: context(SparkTrailFilter.descriptor, [FilterParticles.Param.spread: .number(0), FilterParticles.Param.count: .number(5)]),
        )
        let sparks = out.dropLast()
        #expect(sparks.count == 5)
        for spark in sparks {
            let birth = spark.commands.map(\.startTime).min()!
            #expect(birth >= 0 && birth <= 1000)
            // Born on the path, travelling left of where it was born.
            #expect(abs(spark.defaultX - 0.6 * birth) < 1e-6)
            let path = spark.commands.first { $0.kind == .move }!
            if case let .move(sx, _, ex, _) = path.payload { #expect(ex < sx) }
        }
    }

    @Test("a still sprite sheds nothing")
    func sparkStill() {
        #expect(SparkTrailFilter().apply(to: [sprite()], in: context(SparkTrailFilter.descriptor)).count == 1)
    }

    // MARK: - Impact Ring

    @Test("a ring opens and fades where each fast move lands")
    func impactRing() {
        let hopping = sprite(moves: [
            move((0, 240), (300, 240), 0, 500),
            move((300, 240), (300, 100), 1500, 1600),
            move((300, 100), (310, 100), 2000, 2900),
        ])
        let out = ImpactRingFilter().apply(to: [hopping], in: context(ImpactRingFilter.descriptor))
        let rings = out.dropFirst()
        #expect(rings.count == 2, "the slow last move does not ring")
        let first = rings.first!
        #expect(first.defaultX == 300 && first.defaultY == 240)
        #expect(state(first, 500).opacity == 1)
        #expect(state(first, 900).opacity < 0.01)
        #expect(state(first, 900).scaleX > state(first, 550).scaleX)
        #expect(first.filePath.hasPrefix("__builtin__/hoop"))
    }

    @Test("a chain of moves rings only where it stops")
    func impactChain() {
        let chained = sprite(moves: [move((0, 240), (300, 240), 0, 500), move((300, 240), (600, 240), 500, 1000)])
        let out = ImpactRingFilter().apply(to: [chained], in: context(ImpactRingFilter.descriptor))
        #expect(out.count == 2)
        #expect(out[1].defaultX == 600)
    }
}
