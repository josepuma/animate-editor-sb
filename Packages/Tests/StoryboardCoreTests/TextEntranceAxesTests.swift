import Foundation
import Testing

@testable import StoryboardCore

/// In Scatter, Stretch From and Pivot, read from the sprites the evaluator
/// produces for a node placed the way the editor places one.
///
/// Two placements mint two node ids, and the sprite ids carry them: anything
/// compared across placements is compared on commands and positions, never on
/// a whole sprite dump.
@Suite("Text entrance axes")
struct TextEntranceAxesTests {
    private typealias P = TextEffect.Param

    private func sprites(
        _ values: [String: EffectValue] = [:],
        text: String = "abcdef",
        duration: Double = 4000,
        seed: UInt64 = 8371,
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: duration)
        node.values = TextEffect.descriptor.defaultValues
            .merging([P.fadeIn: .number(400), P.stagger: .number(60)]) { _, new in new }
            .merging(values) { _, new in new }
        node.values[P.text] = .text(text)
        node.seed = seed
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    private func commands(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.map { String(reflecting: $0.commands) }
    }

    /// The entrance move's start, per glyph; `nil` where a glyph does not move.
    private func moveStarts(_ sprites: [StoryboardSprite]) -> [(x: Double, y: Double)?] {
        sprites.map { sprite in
            for command in sprite.commands {
                if case let .move(startX, startY, _, _) = command.payload { return (startX, startY) }
            }
            return nil
        }
    }

    private func rotateStarts(_ sprites: [StoryboardSprite]) -> [Double?] {
        sprites.map { sprite in
            for command in sprite.commands {
                if case let .rotate(start, _) = command.payload { return start }
            }
            return nil
        }
    }

    private func scaleStarts(_ sprites: [StoryboardSprite]) -> [Double?] {
        sprites.map { sprite in
            for command in sprite.commands {
                if case let .scale(start, _) = command.payload { return start }
            }
            return nil
        }
    }

    /// Every glyph's value, or a failed test: a force-unwrap here would take
    /// the whole runner down under a mutation, and a suite that dies leaves
    /// nothing to read.
    private func every<T>(_ values: [T?]) throws -> [T] {
        let found = values.compactMap { $0 }
        try #require(!found.isEmpty && found.count == values.count)
        return found
    }

    // ─── In Scatter ──────────────────────────────────────────────────────────

    private let scattered: [String: EffectValue] = [
        P.scatterX: .number(200), P.scatterY: .number(150),
        P.scatterRotation: .number(90), P.scatterScale: .number(0.5),
    ]

    /// S5.1
    @Test("scatter is deterministic")
    func deterministic() {
        #expect(commands(sprites(scattered)) == commands(sprites(scattered)))
    }

    /// S5.2
    @Test("another seed scatters differently")
    func seedMatters() {
        #expect(commands(sprites(scattered, seed: 1)) != commands(sprites(scattered, seed: 2)))
    }

    /// S5.3: the scatter draws come from a stream of their own, so Explode and
    /// Drift — which draw from the glyph's stream — take the same headings.
    @Test("Explode and Drift are untouched by scatter", arguments: ["Explode", "Drift"])
    func exitUntouched(exit: String) {
        let base: [String: EffectValue] = [
            P.fadeOut: .number(800), P.exit: .choice(exit), P.exitForce: .number(300),
        ]
        // The exit's own move and tumble: everything that starts with the exit
        // other than the fade-out.
        func exits(_ sprites: [StoryboardSprite]) -> [String] {
            sprites.map { sprite in
                String(reflecting: sprite.commands.filter { command in
                    guard command.startTime == 4000 - 800 else { return false }
                    if case .fade = command.payload { return false }
                    return true
                })
            }
        }
        let plain = exits(sprites(base))
        let withScatter = exits(sprites(base.merging(scattered) { $1 }))
        #expect(plain.allSatisfy { $0.contains("rotate") })
        #expect(withScatter == plain)
    }

    /// S5.4: appending recentres the line, so absolute positions move; what
    /// must not move is each glyph's own jitter.
    @Test("adding characters at the end keeps the scatter already placed")
    func appendingKeepsScatter() throws {
        func jitters(_ text: String) throws -> [String] {
            let all = sprites(scattered, text: text)
            let moves = try every(moveStarts(all))
            let turns = try every(rotateStarts(all))
            let sizes = try every(scaleStarts(all))
            return all.indices.map { i in
                "\(moves[i].x - all[i].defaultX) \(moves[i].y - all[i].defaultY) \(turns[i]) \(sizes[i])"
            }
        }
        let short = try jitters("abc")
        #expect(short == Array(try jitters("abcxyz").prefix(3)))
        #expect(Set(short).count == 3)
    }

    /// S5.5: each axis on its own moves only what it names.
    @Test("Scatter X spreads the start horizontally only")
    func scatterX() throws {
        let all = sprites([P.scatterX: .number(200)])
        let starts = try every(moveStarts(all))
        let plain = sprites().map { ($0.defaultX, $0.defaultY) }
        // The other axes stay out of the file entirely, not in it as zeroes.
        #expect(rotateStarts(all).allSatisfy { $0 == nil })
        #expect(scaleStarts(all).allSatisfy { $0 == nil })
        #expect(Set(zip(starts, plain).map { $0.x - $1.0 }).count == starts.count)
        #expect(zip(starts, plain).allSatisfy { $0.y == $1.1 })
        #expect(zip(starts, plain).allSatisfy { abs($0.x - $1.0) <= 200 })
    }

    @Test("Scatter Y spreads the start vertically only")
    func scatterY() throws {
        let starts = try every(moveStarts(sprites([P.scatterY: .number(150)])))
        let plain = sprites().map { ($0.defaultX, $0.defaultY) }
        #expect(Set(zip(starts, plain).map { $0.y - $1.1 }).count == starts.count)
        #expect(zip(starts, plain).allSatisfy { $0.x == $1.0 })
    }

    @Test("Scatter Rotation gives each glyph its own starting angle")
    func scatterRotation() throws {
        let starts = try every(rotateStarts(sprites([P.scatterRotation: .number(90)])))
        #expect(Set(starts).count == starts.count)
        #expect(starts.allSatisfy { abs($0) <= .pi / 2 })
        #expect(rotateStarts(sprites()).allSatisfy { $0 == nil })
    }

    @Test("Scatter Scale gives each glyph its own starting size")
    func scatterScale() throws {
        let starts = try every(scaleStarts(sprites([P.scatterScale: .number(0.5)])))
        #expect(Set(starts).count == starts.count)
        #expect(starts.allSatisfy { $0 >= 0.5 && $0 <= 1.5 })
        #expect(scaleStarts(sprites()).allSatisfy { $0 == nil })
    }

    /// Scatter adds to the move it is given, not replaces it.
    @Test("scatter adds to Rise and Drift")
    func addsToEntrance() throws {
        let base: [String: EffectValue] = [P.riseFrom: .number(40), P.driftFrom: .number(-100)]
        let plain = try every(moveStarts(sprites(base)))
        let jittered = try every(moveStarts(sprites(base.merging([P.scatterX: .number(10)]) { $1 })))
        #expect(zip(plain, jittered).allSatisfy { $0.y == $1.y && abs($0.x - $1.x) <= 10 })
        #expect(zip(plain, jittered).contains { $0.x != $1.x })
    }

    /// S5.6
    @Test("a word arrives together but scatters per glyph")
    func unitSharesDelayNotScatter() throws {
        let all = sprites([P.unit: .choice("Word"), P.scatterX: .number(200)], text: "ab cd")
        let arrivals = all.map { $0.commands.first?.startTime }
        #expect(arrivals[0] == arrivals[1])
        let starts = try every(moveStarts(all))
        #expect(starts[0].x - all[0].defaultX != starts[1].x - all[1].defaultX)
    }

    // ─── Stretch From ────────────────────────────────────────────────────────

    private func hasScale(_ sprite: StoryboardSprite) -> Bool {
        sprite.commands.contains { if case .scale = $0.payload { true } else { false } }
    }

    private func vectors(_ sprite: StoryboardSprite) -> [Command] {
        sprite.commands.filter { if case .vectorScale = $0.payload { true } else { false } }
    }

    /// S6.1
    @Test("no stretch writes no vector scale")
    func noStretchNoVector() {
        let all = sprites([P.scaleFrom: .number(0.4), P.fadeOut: .number(300), P.exit: .choice("Shrink")])
        #expect(all.allSatisfy(hasScale))
        #expect(all.allSatisfy { vectors($0).isEmpty })
    }

    /// S6.2: both axes written, the one at 1 included, starting at (X, Y)
    /// times the resting scale.
    @Test("a stretch enters as a vector from the stretched size", arguments: [
        (1.0, 0.05, 1.0), (3.0, 0.2, 0.5), (0.05, 1.0, 1.4),
    ])
    func stretchEntrance(x: Double, y: Double, scaleFrom: Double) throws {
        let all = sprites([P.stretchFromX: .number(x), P.stretchFromY: .number(y), P.scaleFrom: .number(scaleFrom)])
        for sprite in all {
            let entrance = try #require(vectors(sprite).first)
            guard case let .vectorScale(startX, startY, endX, endY) = entrance.payload else {
                Issue.record("not a vector"); return
            }
            #expect(startX == scaleFrom * x)
            #expect(startY == scaleFrom * y)
            #expect(endX == 1 && endY == 1)
            #expect(entrance.endTime - entrance.startTime == 400)
        }
    }

    /// S6.3 / S6.4: a stretched sprite never mixes `S` and `V` — Shrink and
    /// Grow leave as vectors too.
    @Test("a stretched sprite leaves as a vector", arguments: ["Shrink", "Grow"])
    func stretchExit(exit: String) throws {
        let all = sprites([
            P.stretchFromY: .number(0.05), P.fadeOut: .number(300), P.exit: .choice(exit),
            P.scaleFrom: .number(0.5), P.scatterScale: .number(0.3),
        ])
        for sprite in all {
            #expect(!hasScale(sprite), "\(exit): a stretched sprite wrote S")
            let leaving = try #require(vectors(sprite).last)
            guard case let .vectorScale(startX, startY, endX, endY) = leaving.payload else { return }
            let to = exit == "Shrink" ? 0.2 : 2.0
            #expect(startX == 1 && startY == 1 && endX == to && endY == to)
            #expect(leaving.endTime == 4000)
        }
    }

    /// S6.6
    @Test("a stretch writes nothing outside the sprite's life")
    func stretchInsideLife() {
        let all = sprites([P.stretchFromX: .number(2), P.fadeOut: .number(300), P.exit: .choice("Grow")])
        for sprite in all {
            let birth = sprite.commands.map(\.startTime).min() ?? 0
            for command in sprite.commands {
                #expect(command.startTime >= birth && command.endTime <= 4000)
            }
        }
    }

    /// S6.5: written, normalised, parsed back and resolved, the file draws
    /// what the preview draws.
    @Test("a stretched line survives the export round trip")
    func stretchRoundTrip() {
        let all = sprites([
            P.stretchFromX: .number(3), P.stretchFromY: .number(0.2), P.scaleFrom: .number(0.6),
            P.fadeOut: .number(300), P.exit: .choice("Shrink"), P.riseFrom: .number(30),
        ])
        let parsed = OsbParser.parse(OsbWriter.write(OsbExportNormalization.normalize(all))).sprites
        #expect(parsed.count == all.count)

        var compared = 0
        for time in stride(from: 0.0, through: 4000, by: 125) {
            var before: [SpriteRenderState] = []
            var after: [SpriteRenderState] = []
            StoryboardResolver.resolve(StoryboardResolver.prepare(all), at: time, into: &before)
            StoryboardResolver.resolve(StoryboardResolver.prepare(parsed), at: time, into: &after)
            #expect(before.count == after.count, "live count differs at \(time)")
            for (a, b) in zip(before, after) {
                var b = b
                b.spriteId = a.spriteId
                // The file rounds times to whole milliseconds and values to
                // three decimals; the picture has to agree within that.
                #expect(abs(a.scaleX - b.scaleX) < 0.01 && abs(a.scaleY - b.scaleY) < 0.01, "at \(time)")
                #expect(abs(a.opacity - b.opacity) < 0.01, "at \(time)")
                compared += 1
            }
        }
        #expect(compared > 0)
    }

    // ─── Pivot ───────────────────────────────────────────────────────────────

    /// The height Core predicts for a glyph's texture — the renderer suite
    /// draws real glyphs to hold it to the pixels.
    private func box(_ character: Character) -> Double {
        TextSprite.boxHeight(TextMetrics.glyph(character, style: TextStyle()), style: TextStyle())
    }

    /// Where the bottom edge of a glyph's box is drawn, from the origin the
    /// sprite declares: Centre hangs half the box below its position, Bottom
    /// none of it.
    private func bottomEdge(_ state: SpriteRenderState, origin: Origin, height: Double) -> Double {
        origin == .bottomCentre ? state.y : state.y + height * state.scaleY / 2
    }

    /// S7.1
    @Test("Centre keeps the centred origin")
    func centrePivot() {
        let all = sprites([P.pivot: .choice("Centre")])
        #expect(all.allSatisfy { $0.origin == .centre })
    }

    /// S7.2: anchored on the box's bottom edge, but drawn where Centre draws it.
    @Test("Bottom anchors on the box's bottom edge without moving the glyph")
    func bottomPivotSamePlace() {
        let centre = sprites(text: "Ag")
        let bottom = sprites([P.pivot: .choice("Bottom")], text: "Ag")
        #expect(bottom.allSatisfy { $0.origin == .bottomCentre })
        for (c, b) in zip(centre, bottom) {
            #expect(b.defaultX == c.defaultX)
            #expect(b.defaultY - box("A") / 2 == c.defaultY)
        }
        #expect(box("A") > TextMetrics.glyph("A", style: TextStyle()).height, "the box includes its padding")
    }

    /// S7.3: a scaling entrance grows out of the bottom edge, which holds.
    @Test("Bottom holds the bottom edge while the glyph scales", arguments: ["Centre", "Bottom"])
    func bottomEdgeHolds(pivot: String) throws {
        let all = sprites([P.pivot: .choice(pivot), P.scaleFrom: .number(0.2)], text: "a")
        let sprite = try #require(all.first)
        func edge(at time: Double) throws -> Double {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time, into: &states)
            return bottomEdge(try #require(states.first), origin: sprite.origin, height: box("a"))
        }
        let moved = abs(try edge(at: 1) - edge(at: 400))
        if pivot == "Bottom" { #expect(moved < 1e-9) } else { #expect(moved > 10) }
    }

    /// S7.4
    @Test("Bottom keeps the layout's spacing over several lines")
    func bottomMultiline() {
        let centre = sprites(text: "ab\ncd\nef")
        let bottom = sprites([P.pivot: .choice("Bottom")], text: "ab\ncd\nef")
        #expect(centre.map(\.defaultX) == bottom.map(\.defaultX))
        let gaps = { (all: [StoryboardSprite]) in zip(all, all.dropFirst()).map { $1.defaultY - $0.defaultY } }
        #expect(gaps(centre) == gaps(bottom))
    }

    // ─── Every parameter ─────────────────────────────────────────────────────

    /// S9.6 for this slice's axes. The signature carries origin and position
    /// besides the commands, because Pivot at rest changes nothing else; and
    /// never the sprite id, which embeds a per-placement node id and would
    /// make any two placements "differ".
    @Test("each entrance axis changes the output", arguments: [
        (P.scatterX, EffectValue.number(120)),
        (P.scatterY, .number(80)),
        (P.scatterRotation, .number(45)),
        (P.scatterScale, .number(0.4)),
        (P.stretchFromX, .number(0.3)),
        (P.stretchFromY, .number(2.5)),
        (P.pivot, .choice("Bottom")),
    ])
    func everyAxisMatters(id: String, value: EffectValue) {
        func signature(_ values: [String: EffectValue]) -> [String] {
            sprites(values, text: "ab cd").map {
                "\($0.origin) \($0.defaultX) \($0.defaultY) " + String(reflecting: $0.commands)
            }
        }
        let base: [String: EffectValue] = [P.fadeOut: .number(300)]
        #expect(signature(base.merging([id: value]) { $1 }) != signature(base), "\(id)")
    }
}
