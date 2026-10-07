import Foundation
import Testing

@testable import StoryboardCore

/// Colour modes, read from the `_C` commands written and the colour resolved.
@Suite("Text colour")
struct TextColourTests {
    private typealias P = TextEffect.Param

    private static let red = EffectColor(r: 255, g: 0, b: 0)
    private static let blue = EffectColor(r: 0, g: 0, b: 255)

    private func node(_ values: [String: EffectValue], text: String, duration: Double = 3000) -> EffectNode {
        Phase1SnapshotTests.node(text: text, seed: 8371, duration: duration, values: values)
    }

    private func sprites(_ values: [String: EffectValue], text: String = "abcde", duration: Double = 3000) -> [StoryboardSprite] {
        Phase1SnapshotTests.production(node(values, text: text, duration: duration))
    }

    private func colour(_ sprite: StoryboardSprite, at time: Double) throws -> [Double] {
        let state = try #require(StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time).first)
        return [state.r, state.g, state.b]
    }

    private func colourCommands(_ sprite: StoryboardSprite) -> [Command] {
        sprite.commands.filter { $0.kind == .color }
    }

    @Test("Solid writes what phase 1 wrote, whatever the other colour controls say")
    func solidIsPhase1() {
        let values: [String: EffectValue] = [
            P.fadeIn: .number(300), P.stagger: .number(40), P.color: .color(Self.red),
            P.colourMode: .choice("Solid"), P.colour2: .color(Self.blue), P.flash: .toggle(true),
            P.sweepLength: .number(20),
        ]
        let subject = node(values, text: "ab cd")
        #expect(Phase1SnapshotTests.dump(Phase1SnapshotTests.production(subject))
            == Phase1SnapshotTests.dump(Phase1SnapshotTests.oracle(subject)))
    }

    @Test("Gradient runs from the first colour to the second across the line")
    func gradientAcrossLine() throws {
        let drawn = sprites([
            P.color: .color(Self.red), P.colourMode: .choice("Gradient"), P.colour2: .color(Self.blue),
        ])
        let reds = try drawn.map { try colour($0, at: 100)[0] }
        #expect(reds.first == 255 && reds.last == 0)
        #expect(reds == reds.sorted(by: >) && Set(reds).count == reds.count)
        #expect(try colour(drawn[drawn.count - 1], at: 100) == [0, 0, 255])
        #expect(drawn.allSatisfy { colourCommands($0).count == 1 })
    }

    /// Line restarts on each line; Block runs once over the whole text.
    @Test("Gradient spans a line or the whole block")
    func gradientLineOrBlock() throws {
        let values: [String: EffectValue] = [
            P.color: .color(Self.red), P.colourMode: .choice("Gradient"), P.colour2: .color(Self.blue),
        ]
        let lines = sprites(values.merging([P.gradientAcross: .choice("Line")]) { _, new in new }, text: "ab\nwxyz")
        #expect(try colour(lines[0], at: 10)[0] == 255 && colour(lines[2], at: 10)[0] == 255)
        #expect(try colour(lines[1], at: 10)[0] == 0 && colour(lines[5], at: 10)[0] == 0)
        let block = sprites(values.merging([P.gradientAcross: .choice("Block")]) { _, new in new }, text: "ab\nwxyz")
        #expect(try colour(block[1], at: 10)[0] > 0 && colour(block[1], at: 10)[0] < 255)
        #expect(try colour(block[2], at: 10)[0] == 255 && colour(block[5], at: 10)[0] == 0)
    }

    /// Each glyph changes on its own turn, in the sweep's order, from the
    /// base it has held since birth — without a second `_C` restating it.
    @Test("Highlight sweeps in order", arguments: ["Start", "End"])
    func highlightSweeps(order: String) throws {
        let drawn = sprites([
            P.color: .color(Self.red), P.colourMode: .choice("Highlight"), P.colour2: .color(Self.blue),
            P.sweepOrder: .choice(order), P.sweepStart: .number(10), P.sweepLength: .number(60),
            P.sweepEdge: .number(100),
        ])
        let starts = try drawn.map { try #require(colourCommands($0).first).startTime }
        #expect(starts == (order == "Start" ? starts.sorted() : starts.sorted(by: >)))
        #expect(Set(starts).count == starts.count)
        for (sprite, start) in zip(drawn, starts) {
            #expect(colourCommands(sprite).count == 1, "no duplicated base")
            #expect(try colour(sprite, at: start - 1) == [255, 0, 0])
            #expect(try colour(sprite, at: start + 101) == [0, 0, 255])
        }
    }

    @Test("Flash returns to the base colour")
    func flashReturns() throws {
        let drawn = sprites([
            P.color: .color(Self.red), P.colourMode: .choice("Highlight"), P.colour2: .color(Self.blue),
            P.sweepEdge: .number(100), P.flash: .toggle(true),
        ])
        for sprite in drawn {
            let start = try #require(colourCommands(sprite).first).startTime
            #expect(try colour(sprite, at: start + 100) == [0, 0, 255])
            #expect(try colour(sprite, at: 2900) == [255, 0, 0])
            #expect(colourCommands(sprite).count == 2)
        }
    }

    /// The sweep never colours a glyph before it exists, never writes past its
    /// life, and costs at most three `_C` per glyph whatever the mode.
    @Test("colour stays inside each glyph's life and its budget", arguments: ["Solid", "Gradient", "Highlight"])
    func bounded(mode: String) {
        for (flash, sweepStart) in [(false, 0.0), (true, 0.0), (false, 95.0), (true, 95.0)] {
            let drawn = sprites([
                P.fadeIn: .number(300), P.fadeOut: .number(300), P.stagger: .number(300),
                P.color: .color(Self.red), P.colourMode: .choice(mode), P.colour2: .color(Self.blue),
                // A sweep faster than the stagger reaches glyphs before they
                // exist; the last one is due when its life has ended.
                P.sweepStart: .number(sweepStart), P.sweepLength: .number(20), P.sweepEdge: .number(400),
                P.flash: .toggle(flash),
            ])
            for sprite in drawn {
                let birth = sprite.commands.filter { $0.kind == .fade }.map(\.startTime).min() ?? 0
                let death = sprite.commands.filter { $0.kind == .fade }.map(\.endTime).max() ?? 0
                let colours = colourCommands(sprite)
                #expect(!colours.isEmpty && colours.count <= 3, "\(mode)")
                #expect(colours.allSatisfy {
                    $0.startTime >= birth && $0.startTime <= $0.endTime && $0.endTime <= death
                }, "\(mode) \(flash) \(sweepStart)")
                #expect(TextOverlapGuard.violations(sprite).isEmpty)
            }
        }
    }
}
