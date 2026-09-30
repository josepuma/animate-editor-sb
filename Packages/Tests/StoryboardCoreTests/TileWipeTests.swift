import Foundation
import Testing

@testable import StoryboardCore

/// A grid of hard squares sweeping across the stage as a rippling curtain:
/// cells pop in, hold while the screen is covered, and pop out.
///
/// Everything here is measured from the sprites that come out, resolved at a
/// moment in time — the same route the renderer takes. Reading the effect's own
/// numbers would agree with any formula.
@Suite("Tile wipe")
struct TileWipeTests {
    private typealias Param = TileWipeEffect.Param

    /// Only this effect: it is not in `EffectLibrary.standard` yet, and a test
    /// that reaches it through the standard library would be testing the
    /// registration rather than the wipe.
    private let evaluator = EffectEvaluator(library: EffectLibrary(effects: [TileWipeEffect()]))

    private static let stageLeft = -107.0
    private static let stageWidth = 854.0
    private static let stageHeight = 480.0

    private func node(_ overrides: [String: EffectValue] = [:], duration: Double = 2400) -> EffectNode {
        EffectNode(
            id: "wipe", type: TileWipeEffect.descriptor.type, name: "Wipe",
            startTime: 0, duration: duration, seed: 3,
            values: TileWipeEffect.descriptor.defaultValues.merging(overrides) { _, new in new },
        )
    }

    private func sprites(_ overrides: [String: EffectValue] = [:], duration: Double = 2400) -> [StoryboardSprite] {
        evaluator.evaluate(node(overrides, duration: duration))
    }

    /// One cell, read back from its sprite: where it sits in the lattice and
    /// when it starts to pop in.
    private struct Cell {
        var column: Int
        var row: Int
        var landsAt: Double
    }

    private func cells(
        _ sprites: [StoryboardSprite], columns: Int = 16, rows: Int = 9,
    ) -> [Cell] {
        let pitchX = Self.stageWidth / Double(columns)
        let pitchY = Self.stageHeight / Double(rows)
        return sprites.map { sprite in
            let landsAt = sprite.commands
                .filter { if case .vectorScale = $0.payload { true } else { false } }
                .map(\.timing.startTime).min() ?? .nan
            return Cell(
                column: Int(((sprite.defaultX - Self.stageLeft) / pitchX - 0.5).rounded()),
                row: Int((sprite.defaultY / pitchY - 0.5).rounded()),
                landsAt: landsAt,
            )
        }
    }

    private struct Rect {
        var minX: Double, maxX: Double, minY: Double, maxY: Double
    }

    /// What is on screen at `time`, as rectangles in stage units.
    private func drawn(_ sprites: [StoryboardSprite], at time: Double) -> [Rect] {
        let prepared = StoryboardResolver.prepare(sprites)
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: time, into: &states)
        let side = ShapeEffect.sourceSize
        return states.compactMap { state in
            guard state.visible, state.opacity > 0.02 else { return nil }
            let halfW = Double(state.scaleX) * side / 2
            let halfH = Double(state.scaleY) * side / 2
            guard halfW > 0.001, halfH > 0.001 else { return nil }
            return Rect(
                minX: Double(state.x) - halfW, maxX: Double(state.x) + halfW,
                minY: Double(state.y) - halfH, maxY: Double(state.y) + halfH,
            )
        }
    }

    // ─── Cover ───────────────────────────────────────────────────────────────

    /// The point of a wipe: while it holds, no pixel of the stage is left
    /// showing. Sampled on a lattice whose step does not divide the pitch, so
    /// the samples land on and around the seams instead of politely between
    /// them.
    @Test("held, the cells cover every point of the stage")
    func coversTheStage() {
        let all = sprites()
        let rects = drawn(all, at: 1200)
        #expect(rects.count == all.count, "\(rects.count) of \(all.count) cells are up")

        var uncovered: [(Double, Double)] = []
        var y = 0.0
        while y <= Self.stageHeight {
            var x = Self.stageLeft
            while x <= Self.stageLeft + Self.stageWidth {
                if !rects.contains(where: { $0.minX <= x && x <= $0.maxX && $0.minY <= y && y <= $0.maxY }) {
                    uncovered.append((x, y))
                }
                x += 1.37
            }
            y += 1.37
        }
        #expect(uncovered.isEmpty, "\(uncovered.count) uncovered, first \(uncovered.first ?? (0, 0))")
    }

    @Test("the stage is empty before the wipe and after it")
    func emptyOutside() {
        let all = sprites()
        #expect(drawn(all, at: -50).isEmpty)
        #expect(drawn(all, at: 2400 + 100).isEmpty)
    }

    /// Two hard rectangles that meet exactly leave a hairline: each covers half
    /// of the seam pixel, and two half-covered pixels do not add up to a whole
    /// one. With no gap the cells therefore have to overlap a little.
    @Test("with no gap, neighbouring cells overlap rather than merely touch")
    func noSeams() throws {
        let rects = drawn(sprites([Param.gap: .number(0)]), at: 1200)
        let sorted = rects.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
        let firstRow = sorted.prefix(16)
        for (left, right) in zip(firstRow, firstRow.dropFirst()) {
            #expect(right.minX < left.maxX - 0.4, "seam between \(left.maxX) and \(right.minX)")
        }

        let firstColumn = rects.filter { $0.minX == rects.map(\.minX).min() }.sorted { $0.minY < $1.minY }
        #expect(firstColumn.count == 9)
        for (above, below) in zip(firstColumn, firstColumn.dropFirst()) {
            #expect(below.minY < above.maxY - 0.4, "seam between \(above.maxY) and \(below.minY)")
        }
    }

    // ─── Gap ─────────────────────────────────────────────────────────────────

    /// The LED-meter look: the same lattice, smaller cells, visible spacing.
    @Test("gap sets the spacing between cells without moving them")
    func gapSpacesCells() throws {
        func row(_ gap: Double) -> [Rect] {
            drawn(sprites([Param.gap: .number(gap)]), at: 1200)
                .sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
                .prefix(16).map { $0 }
        }
        let solid = row(0)
        let spaced = row(10)

        // Same pitch: centres do not move.
        let solidCentres = solid.map { ($0.minX + $0.maxX) / 2 }
        let spacedCentres = spaced.map { ($0.minX + $0.maxX) / 2 }
        for (a, b) in zip(solidCentres, spacedCentres) { #expect(abs(a - b) < 0.01) }

        // The distance between neighbouring edges is the gap.
        for (left, right) in zip(spaced, spaced.dropFirst()) {
            #expect(abs((right.minX - left.maxX) - 10) < 0.05, "gap \(right.minX - left.maxX)")
        }

        // And it is a real gap: the seam between two cells is not covered.
        let seam = (spaced[0].maxX + spaced[1].minX) / 2
        let midY = (spaced[0].minY + spaced[0].maxY) / 2
        let all = drawn(sprites([Param.gap: .number(10)]), at: 1200)
        #expect(!all.contains { $0.minX <= seam && seam <= $0.maxX && $0.minY <= midY && midY <= $0.maxY })

        // The gap also opens between rows.
        let column = all.filter { $0.minX == all.map(\.minX).min() }.sorted { $0.minY < $1.minY }
        for (above, below) in zip(column, column.dropFirst()) {
            #expect(abs((below.minY - above.maxY) - 10) < 0.05)
        }
    }

    // ─── Sweep, wave, direction ──────────────────────────────────────────────

    private func meanLanding(_ cells: [Cell], where include: (Cell) -> Bool) -> Double {
        let chosen = cells.filter(include)
        return chosen.map(\.landsAt).reduce(0, +) / Double(chosen.count)
    }

    @Test("the leading edge lands before the trailing one, in every direction", arguments: [
        ("Left to Right", true, true), ("Right to Left", true, false),
        ("Top to Bottom", false, true), ("Bottom to Top", false, false),
    ])
    func direction(name: String, horizontal: Bool, forward: Bool) {
        let all = cells(sprites([Param.direction: .choice(name)]))
        let first = horizontal ? 0 : 0
        let lastColumn = 15, lastRow = 8

        func edge(_ index: Int) -> Double {
            meanLanding(all) { horizontal ? $0.column == index : $0.row == index }
        }
        let near = forward ? edge(first) : edge(horizontal ? lastColumn : lastRow)
        let far = forward ? edge(horizontal ? lastColumn : lastRow) : edge(first)
        #expect(near < far - 50, "\(name): leading \(near), trailing \(far)")
    }

    /// Each column lands after the one before it — a front, not a scatter.
    @Test("columns land in order")
    func columnsInOrder() {
        let all = cells(sprites([Param.wave: .number(0)]))
        let means = (0 ..< 16).map { column in meanLanding(all) { $0.column == column } }
        for (a, b) in zip(means, means.dropFirst()) { #expect(a < b) }
    }

    /// The front is a wave: the rows of one column land at different times, and
    /// those times rise and fall rather than climbing steadily.
    @Test("the front is a wave across the rows")
    func frontIsWavy() {
        let all = cells(sprites())
        let column = all.filter { $0.column == 8 }.sorted { $0.row < $1.row }.map(\.landsAt)
        #expect(column.count == 9)
        #expect((column.max() ?? 0) - (column.min() ?? 0) > 100, "spread \(column)")

        let turns = zip(zip(column, column.dropFirst()), column.dropFirst().dropFirst())
            .count { ($0.0.1 - $0.0.0) * ($0.1 - $0.0.1) < 0 }
        #expect(turns >= 2, "the times never turn: \(column)")
    }

    @Test("with no wave the front is a straight line")
    func flatFront() {
        let all = cells(sprites([Param.wave: .number(0)]))
        for column in 0 ..< 16 {
            let times = all.filter { $0.column == column }.map(\.landsAt)
            #expect((times.max() ?? 0) - (times.min() ?? 0) < 0.5, "column \(column): \(times)")
        }
    }

    /// The wave comes out on the perpendicular axis, so a vertical sweep ripples
    /// across its columns.
    @Test("a vertical sweep ripples across the columns")
    func verticalWave() {
        let all = cells(sprites([Param.direction: .choice("Top to Bottom")]))
        let row = all.filter { $0.row == 4 }.sorted { $0.column < $1.column }.map(\.landsAt)
        #expect((row.max() ?? 0) - (row.min() ?? 0) > 100, "\(row)")
    }

    // ─── Lifecycle, cost, family rules ───────────────────────────────────────

    /// In from nothing, out to nothing, and never lit.
    @Test("each cell pops in from zero and out to zero, hard-edged and not additive")
    func lifecycle() {
        for sprite in sprites() {
            #expect(sprite.filePath == BuiltInSprite.fill)
            #expect(!sprite.commands.contains { if case .parameter = $0.payload { true } else { false } })

            let scales = sprite.commands.compactMap { command -> (Double, Double)? in
                if case let .vectorScale(sx, _, ex, _) = command.payload { return (sx, ex) }
                return nil
            }
            #expect(scales.count == 2)
            #expect(scales.first?.0 == 0, "starts from nothing")
            #expect(scales.last?.1 == 0, "ends at nothing")
            #expect((scales.first?.1 ?? 0) > 0)
        }
    }

    /// 16 × 9 cells, each with two scale commands and no colour when white.
    @Test("the default grid is 144 cells and a few hundred commands")
    func cost() {
        let all = sprites()
        #expect(all.count == 144)
        let commands = all.reduce(0) { $0 + $1.commands.count }
        #expect(commands <= 144 * 3, "\(commands) commands")
    }

    @Test("the wipe stays inside its clip")
    func staysInClip() {
        for sprite in sprites() {
            for command in sprite.commands {
                #expect(command.timing.startTime >= 0)
                #expect(command.timing.endTime <= 2400 + 0.001)
            }
        }
    }

    @Test("colour is one command per cell, and white writes none")
    func colour() {
        let tinted = sprites([Param.color: .color(EffectColor(r: 230, g: 195, b: 65))])
        #expect(tinted.allSatisfy { sprite in
            sprite.commands.contains { if case .color = $0.payload { true } else { false } }
        })
        #expect(!sprites().contains { sprite in
            sprite.commands.contains { if case .color = $0.payload { true } else { false } }
        })
    }

    @Test("more columns and rows mean more cells, still covering the stage")
    func gridSize() {
        let all = sprites([Param.columns: .integer(8), Param.rows: .integer(5)])
        #expect(all.count == 40)
        let rects = drawn(all, at: 1200)
        #expect(rects.map(\.minX).min()! <= Self.stageLeft)
        #expect(rects.map(\.maxX).max()! >= Self.stageLeft + Self.stageWidth)
        #expect(rects.map(\.minY).min()! <= 0)
        #expect(rects.map(\.maxY).max()! >= Self.stageHeight)
    }

    @Test("the preset is a Flat one, complete, and yellow")
    func preset() throws {
        let preset = try #require(TileWipeEffect.presets.first { $0.id == "tile-wipe" })
        #expect(preset.pack == "Flat")
        #expect(preset.effectType == TileWipeEffect.descriptor.type)
        let declared = Set(TileWipeEffect.descriptor.parameters.map(\.id))
        #expect(declared.isSubset(of: Set(preset.values.keys)))
        #expect(preset.values[Param.color] != .color(.white))
    }
}
