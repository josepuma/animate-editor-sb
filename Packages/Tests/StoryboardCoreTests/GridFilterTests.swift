import Foundation
import Testing

@testable import StoryboardCore

/// The lattice counterpart to `RadialFilter`: that one arranges copies around a
/// circle, this one lays them out in rows and columns.
@Suite("Grid filter")
struct GridFilterTests {
    private let evaluator = EffectEvaluator()

    private func document() -> EffectDocument {
        var document = EffectDocument()
        _ = document.add(ShapeEffect.descriptor, at: 0, duration: 2000)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    /// A grid with the given shape, spaced far enough apart to tell cells
    /// apart.
    private func grid(
        columns: Int = 3,
        rows: Int = 3,
        spacing: Double = 100,
        delay: Double = 0,
        stagger: GridFilter.Stagger = .rows,
        anchor: GridFilter.Anchor = .centred,
    ) -> EffectDocument {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(GridFilter.descriptor, to: trackID)!

        func set(_ value: EffectValue, _ id: String) {
            document.setFilterValue(value, for: id, on: filter.id, in: trackID)
        }
        set(.integer(columns), GridFilter.Param.columns)
        set(.integer(rows), GridFilter.Param.rows)
        set(.number(spacing), GridFilter.Param.spacingX)
        set(.number(spacing), GridFilter.Param.spacingY)
        set(.number(delay), GridFilter.Param.delay)
        set(.choice(stagger.rawValue), GridFilter.Param.stagger)
        set(.choice(anchor.rawValue), GridFilter.Param.anchor)
        return document
    }

    // ─── Layout ──────────────────────────────────────────────────────────────

    @Test("a grid makes one copy per cell")
    func oneCopyPerCell() {
        #expect(evaluator.evaluate(grid(columns: 4, rows: 3)).count == 12)
        #expect(evaluator.evaluate(grid(columns: 1, rows: 5)).count == 5)
    }

    /// Every filter has to be inert in its defaults: they land in projects that
    /// are already finished, and a default that changed the output would
    /// rewrite approved work. The default here is a 3×3, so "inert" means the
    /// filter has to be *added* to change anything — which is exactly what
    /// `defaultsAreInert` in `FilterTests` checks for every filter.
    @Test("a single cell with no spacing changes nothing")
    func degenerateGridIsInert() {
        let plain = evaluator.evaluate(document())
        let single = evaluator.evaluate(grid(columns: 1, rows: 1))
        #expect(single.count == plain.count)

        // No spacing stacks every copy on the original: sprites paid for and
        // never seen, which is worse than doing nothing.
        let stacked = evaluator.evaluate(grid(columns: 3, rows: 3, spacing: 0))
        #expect(stacked.count == plain.count)
    }

    /// Cells land on the lattice, not in a heap.
    @Test("cells are spaced by the stated distance")
    func cellsAreSpaced() {
        let sprites = evaluator.evaluate(grid(columns: 3, rows: 1, spacing: 100))
        let xs = sprites.map(\.defaultX).sorted()

        #expect(xs.count == 3)
        #expect(abs(xs[1] - xs[0] - 100) < 0.01)
        #expect(abs(xs[2] - xs[1] - 100) < 0.01)
    }

    /// Asked for a screen of tiles, nobody means "and put the first one in the
    /// corner".
    @Test("a centred grid sits around the clip")
    func centredGridIsCentred() {
        let sprites = evaluator.evaluate(grid(columns: 3, rows: 3, spacing: 100))
        let xs = sprites.map(\.defaultX)
        let ys = sprites.map(\.defaultY)

        let midX = (xs.min()! + xs.max()!) / 2
        let midY = (ys.min()! + ys.max()!) / 2

        #expect(abs(midX - TransformProperty.x.defaultValue) < 0.01)
        #expect(abs(midY - TransformProperty.y.defaultValue) < 0.01)
    }

    /// Anchored at the clip it behaves like a duplicate tool: the original
    /// stays put and copies march away from it.
    @Test("an anchored grid leaves the clip where it was")
    func anchoredGridStartsAtTheClip() {
        let plain = evaluator.evaluate(document())
        let sprites = evaluator.evaluate(
            grid(columns: 3, rows: 3, spacing: 100, anchor: .clip),
        )

        #expect(sprites.map(\.defaultX).min()! == plain[0].defaultX)
        #expect(sprites.map(\.defaultY).min()! == plain[0].defaultY)
    }

    /// A particle spends its whole life inside an `_M`, and osu! draws the
    /// command rather than the default — so a cell whose default moved but
    /// whose commands did not snaps back the moment it starts.
    @Test("the offset reaches the commands, not just the default position")
    func offsetReachesCommands() {
        var document = document()
        let trackID = clip(in: document)
        // A clip that actually travels, so there is a movement command to
        // check. A static position writes no command at all — it only sets the
        // sprite's default, which is correct and saves a line per sprite.
        document.setKeyframe(200, for: .x, at: 0, on: document.nodes[0].id)
        document.setKeyframe(400, for: .x, at: 2000, on: document.nodes[0].id)

        let filter = document.addFilter(GridFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(2), for: GridFilter.Param.columns, on: filter.id, in: trackID)
        document.setFilterValue(.integer(1), for: GridFilter.Param.rows, on: filter.id, in: trackID)
        document.setFilterValue(.number(200), for: GridFilter.Param.spacingX, on: filter.id, in: trackID)
        document.setFilterValue(
            .choice(GridFilter.Anchor.clip.rawValue),
            for: GridFilter.Param.anchor, on: filter.id, in: trackID,
        )

        let positions = evaluator.evaluate(document).compactMap { sprite -> Double? in
            sprite.commands.compactMap { command -> Double? in
                switch command.payload {
                case let .move(startX, _, _, _): startX
                case let .moveX(start, _): start
                default: nil
                }
            }.first
        }

        #expect(positions.count == 2, "both cells must carry a movement")
        #expect(abs(positions.max()! - positions.min()! - 200) < 0.01)
    }

    // ─── Rotating as a group ─────────────────────────────────────────────────

    /// A grid on a turning clip: each tile spins where it stands, or the whole
    /// lattice turns as one object.
    private func turningGrid(orbits: Bool) -> EffectDocument {
        var document = document()
        let trackID = clip(in: document)
        // Half a turn over the clip. Degrees, not radians: the transform stores
        // degrees and converts when it writes the command.
        document.setKeyframe(0, for: .rotation, at: 0, on: document.nodes[0].id)
        document.setKeyframe(180, for: .rotation, at: 2000, on: document.nodes[0].id)

        let filter = document.addFilter(GridFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(3), for: GridFilter.Param.columns, on: filter.id, in: trackID)
        document.setFilterValue(.integer(1), for: GridFilter.Param.rows, on: filter.id, in: trackID)
        document.setFilterValue(.number(100), for: GridFilter.Param.spacingX, on: filter.id, in: trackID)
        document.setFilterValue(.toggle(orbits), for: GridFilter.Param.orbits, on: filter.id, in: trackID)
        return document
    }

    /// Where each cell's last movement command leaves it.
    private func endings(_ sprites: [StoryboardSprite]) -> [Double] {
        sprites.compactMap { sprite -> Double? in
            let moves = sprite.commands
                .filter { if case .move = $0.payload { return true }; return false }
                .sorted { $0.startTime < $1.startTime }
            guard case let .move(_, _, endX, _) = moves.last?.payload else { return nil }
            return endX
        }.sorted()
    }

    /// Off, a rotation spins every tile where it stands: a mosaic of pinwheels,
    /// which is what someone tiling a pattern usually wants.
    @Test("without the flag each cell turns in place")
    func cellsTurnInPlace() {
        let sprites = evaluator.evaluate(turningGrid(orbits: false))
        let starts = sprites.map(\.defaultX).sorted()

        #expect(endings(sprites) == starts, "cells must not move from their lattice positions")
    }

    /// On, the cells orbit the middle of the grid and the pattern turns like
    /// one thing.
    ///
    /// The distinction exists only because osu! has no nested sprites: there is
    /// no group to turn, so orbiting has to be baked into each copy's own path.
    @Test("with the flag the lattice turns as one object")
    func latticeOrbits() {
        let sprites = evaluator.evaluate(turningGrid(orbits: true))
        let centre = TransformProperty.x.defaultValue

        // Half a turn swaps the outer cells and leaves the middle alone.
        let ends = endings(sprites)
        #expect(ends.count == 3)
        #expect(abs(ends[0] - (centre - 100)) < 1, "left cell ended at \(ends[0])")
        #expect(abs(ends[1] - centre) < 1, "centre cell ended at \(ends[1])")
        #expect(abs(ends[2] - (centre + 100)) < 1, "right cell ended at \(ends[2])")

        // And they really swapped rather than staying put: the leftmost cell
        // has to finish on the right, which is the half of this that the
        // in-place test would also have passed.
        let leftmost = sprites.min { $0.defaultX < $1.defaultX }!
        let moves = leftmost.commands
            .filter { if case .move = $0.payload { return true }; return false }
            .sorted { $0.startTime < $1.startTime }
        guard case let .move(_, _, endX, _) = moves.last?.payload else {
            Issue.record("expected a move")
            return
        }
        #expect(endX > leftmost.defaultX + 150, "the left cell never crossed over")
    }

    /// A cell sweeps an arc rather than sliding along the chord: the clip is
    /// turning while the sprite moves, and a straight line through a turning
    /// frame is a curve.
    @Test("an orbiting cell follows an arc, not a chord")
    func orbitIsAnArc() {
        let sprites = evaluator.evaluate(turningGrid(orbits: true))

        // The left cell, which travels the furthest.
        let outer = sprites.min { $0.defaultX < $1.defaultX }!
        let moves = outer.commands
            .filter { if case .move = $0.payload { return true }; return false }
            .sorted { $0.startTime < $1.startTime }

        #expect(moves.count > 1, "an arc needs more than one segment")

        // Partway through a half turn the cell is above or below the line its
        // endpoints share — that is what makes it an arc.
        let middle = moves[moves.count / 2]
        guard case let .move(_, startY, _, _) = middle.payload else {
            Issue.record("expected a move")
            return
        }
        let baseline = TransformProperty.y.defaultValue
        #expect(abs(startY - baseline) > 1, "the cell never left the straight line")
    }

    /// The flag has to be inert when off, because it lands in projects that are
    /// already finished.
    @Test("orbiting off changes nothing")
    func orbitingOffIsInert() {
        let plain = evaluator.evaluate(grid(columns: 3, rows: 3))
        let flagged = evaluator.evaluate(turningGrid(orbits: false))
        #expect(plain.count == 9)
        #expect(flagged.count == 3)
    }

    /// A sprite's rotation is not the group's.
    ///
    /// An emitter gives every particle its own tilt — random spread, or
    /// `Align to Motion` — so a filter that read the `_R` commands to find out
    /// how far the *clip* had turned saw one spinning wildly while nothing was
    /// animated at all. Measured on a fire preset with 180° of spread, the
    /// lattice collapsed from cells 100px apart to cells 11px apart, each
    /// orbiting its own random angle.
    ///
    /// The group's motion has to be handed over, not inferred.
    @Test("particle spin does not make the lattice orbit", arguments: [0.0, 90.0, 180.0])
    func particleSpinIsNotGroupRotation(spread: Double) {
        var document = EffectDocument()
        _ = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        let trackID = document.nodes[0].id
        document.setValue(.integer(3), for: EmitterEffect.Param.count, on: trackID)
        // Every particle gets its own tilt — and none of it is the clip turning.
        document.setValue(.number(spread), for: EmitterEffect.Param.rotation, on: trackID)

        let filter = document.addFilter(GridFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(2), for: GridFilter.Param.columns, on: filter.id, in: trackID)
        document.setFilterValue(.integer(1), for: GridFilter.Param.rows, on: filter.id, in: trackID)
        document.setFilterValue(.number(100), for: GridFilter.Param.spacingX, on: filter.id, in: trackID)
        document.setFilterValue(.toggle(true), for: GridFilter.Param.orbits, on: filter.id, in: trackID)

        let columns = Set(evaluator.evaluate(document).map { Int($0.defaultX) }).sorted()

        #expect(columns.count == 2, "expected two columns, got \(columns)")
        #expect(columns[1] - columns[0] == 100, "the lattice collapsed to \(columns)")
    }

    /// An orbit is a polygon, and its corners must not read as a bounce.
    ///
    /// `_M` interpolates in straight lines, so a circle is really a run of
    /// chords — and how far each one cuts inside the true circle grows with the
    /// radius. A fixed eight segments read as smooth at the pivot and as a
    /// visible wobble a hundred pixels out: measured, 7.6px of sag per corner,
    /// eight times a turn.
    ///
    /// Checked across separations because that is exactly what a fixed count
    /// gets wrong: it is only ever right at one radius.
    @Test("an orbit stays round at any spacing", arguments: [40.0, 100.0, 200.0, 400.0])
    func orbitStaysRound(spacing: Double) {
        var document = document()
        let trackID = clip(in: document)
        document.setKeyframe(0, for: .rotation, at: 0, on: document.nodes[0].id)
        document.setKeyframe(360, for: .rotation, at: 2000, on: document.nodes[0].id)

        let filter = document.addFilter(GridFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(3), for: GridFilter.Param.columns, on: filter.id, in: trackID)
        document.setFilterValue(.integer(1), for: GridFilter.Param.rows, on: filter.id, in: trackID)
        document.setFilterValue(.number(spacing), for: GridFilter.Param.spacingX, on: filter.id, in: trackID)
        document.setFilterValue(.toggle(true), for: GridFilter.Param.orbits, on: filter.id, in: trackID)

        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue

        let outer = evaluator.evaluate(document).min { $0.defaultX < $1.defaultX }!
        let moves = outer.commands.filter {
            if case .move = $0.payload { return true }
            return false
        }
        #expect(!moves.isEmpty)

        // The midpoint of each chord is where it cuts closest to the centre.
        for command in moves {
            guard case let .move(startX, startY, endX, endY) = command.payload else { continue }
            let midX = (startX + endX) / 2
            let midY = (startY + endY) / 2
            let radius = (pow(midX - centreX, 2) + pow(midY - centreY, 2)).squareRoot()

            // The filter's tolerance plus a little slack, not a number of its
            // own: precision here is paid for in every frame, so the guard has
            // to ask for what the filter promises rather than for what geometry
            // would like. The bounce this replaced was 7.6px.
            #expect(
                spacing - radius < 2,
                "at \(spacing)px the orbit sags \(spacing - radius)px — that reads as a bounce",
            )
        }
    }

    /// The segments are bought, not given: a cell near the pivot must not pay
    /// for a cut it does not need, because every segment is a line in the file
    /// multiplied by every cell in the grid.
    @Test("a wider orbit buys more segments than a narrow one")
    func segmentsFollowTheRadius() {
        func segmentCount(spacing: Double) -> Int {
            var document = document()
            let trackID = clip(in: document)
            document.setKeyframe(0, for: .rotation, at: 0, on: document.nodes[0].id)
            document.setKeyframe(360, for: .rotation, at: 2000, on: document.nodes[0].id)

            let filter = document.addFilter(GridFilter.descriptor, to: trackID)!
            document.setFilterValue(.integer(3), for: GridFilter.Param.columns, on: filter.id, in: trackID)
            document.setFilterValue(.integer(1), for: GridFilter.Param.rows, on: filter.id, in: trackID)
            document.setFilterValue(.number(spacing), for: GridFilter.Param.spacingX, on: filter.id, in: trackID)
            document.setFilterValue(.toggle(true), for: GridFilter.Param.orbits, on: filter.id, in: trackID)

            let outer = evaluator.evaluate(document).min { $0.defaultX < $1.defaultX }!
            return outer.commands.count { if case .move = $0.payload { return true }; return false }
        }

        #expect(segmentCount(spacing: 40) < segmentCount(spacing: 400))
    }

    // ─── Sequence ────────────────────────────────────────────────────────────

    /// A tiled logo that all lands together is one big object; the same tiles
    /// landing in sequence read as many, which is the reason to have copied
    /// them at all.
    @Test("a delay staggers the cells in time")
    func delayStaggersCells() {
        let together = evaluator.evaluate(grid(columns: 3, rows: 3, delay: 0))
        let sequenced = evaluator.evaluate(grid(columns: 3, rows: 3, delay: 50))

        let sameStart = Set(together.map { $0.commands.map(\.startTime).min() ?? 0 })
        let staggered = Set(sequenced.map { $0.commands.map(\.startTime).min() ?? 0 })

        #expect(sameStart.count == 1, "with no delay every cell starts together")
        #expect(staggered.count > 1, "with a delay they must not")
    }

    /// The sweep *is* the effect once there is a delay, so each order has to
    /// actually reach the commands — four names for the same sequence would be
    /// four controls that do nothing.
    @Test("each order sweeps differently", arguments: GridFilter.Stagger.allCases)
    func ordersDiffer(stagger: GridFilter.Stagger) {
        let sprites = evaluator.evaluate(
            grid(columns: 3, rows: 3, delay: 50, stagger: stagger),
        )

        // Keyed by position, so two orders can be compared cell for cell.
        let byCell = Dictionary(
            uniqueKeysWithValues: sprites.map { sprite in
                (
                    "\(Int(sprite.defaultX)),\(Int(sprite.defaultY))",
                    sprite.commands.map(\.startTime).min() ?? 0
                )
            },
        )

        let rows = evaluator.evaluate(grid(columns: 3, rows: 3, delay: 50, stagger: .rows))
        let reference = Dictionary(
            uniqueKeysWithValues: rows.map { sprite in
                (
                    "\(Int(sprite.defaultX)),\(Int(sprite.defaultY))",
                    sprite.commands.map(\.startTime).min() ?? 0
                )
            },
        )

        if stagger == .rows {
            #expect(byCell == reference)
        } else {
            #expect(byCell != reference, "\(stagger.rawValue) sweeps the same way as rows")
        }
    }

    /// The centre goes first and the corners last, which is what an impact
    /// looks like.
    @Test("from-centre starts in the middle")
    func outwardStartsInTheMiddle() {
        let sprites = evaluator.evaluate(
            grid(columns: 3, rows: 3, delay: 50, stagger: .outward),
        )

        // Both axes: a 3×3 has three cells sharing the middle column, so
        // "nearest in x" picks a corner and proves nothing.
        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue
        func distance(_ sprite: StoryboardSprite) -> Double {
            (pow(sprite.defaultX - centreX, 2) + pow(sprite.defaultY - centreY, 2)).squareRoot()
        }

        let middle = sprites.min { distance($0) < distance($1) }!
        let corner = sprites.max { distance($0) < distance($1) }!

        func start(_ sprite: StoryboardSprite) -> Double {
            sprite.commands.map(\.startTime).min() ?? 0
        }

        #expect(start(middle) == sprites.map(start).min()!, "the centre must go first")
        #expect(start(corner) > start(middle), "the corners must go last")
    }

    /// The last cell starts after every one before it and still has its whole
    /// life to live, so the block has to say so — a timeline that says a clip
    /// is over while it is still playing is a timeline nobody can arrange
    /// against.
    @Test("a staggered grid reports the longer duration")
    func staggerExtendsTheClip() {
        var document = document()
        let trackID = clip(in: document)
        let filter = document.addFilter(GridFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(3), for: GridFilter.Param.columns, on: filter.id, in: trackID)
        document.setFilterValue(.integer(3), for: GridFilter.Param.rows, on: filter.id, in: trackID)
        document.setFilterValue(.number(50), for: GridFilter.Param.delay, on: filter.id, in: trackID)

        let node = document.nodes[0]
        // Eight delays past the first cell, on top of the clip itself.
        #expect(evaluator.duration(of: 2000, on: node) == 2000 + 8 * 50)
    }

    @Test("with no delay the clip keeps its length")
    func noDelayKeepsTheLength() {
        let document = grid(columns: 3, rows: 3, delay: 0)
        #expect(evaluator.duration(of: 2000, on: document.nodes[0]) == 2000)
    }

    // ─── Cost ────────────────────────────────────────────────────────────────

    /// The steepest multiplier in the library, and it multiplies: a 5×5 over a
    /// two-hundred particle emitter is five thousand sprites. Worth knowing
    /// while it can still be turned down.
    @Test("the multiplier reports rows times columns")
    func multiplierIsHonest() {
        let document = grid(columns: 4, rows: 5)
        #expect(evaluator.spriteMultiplier(for: document.nodes[0]) == 20)
    }
}
