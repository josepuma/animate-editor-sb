import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// The scripts under `Examples/` run.
///
/// An example nobody runs is an example that can rot in place: it names a
/// method that gets renamed, or an easing that does not exist, and nothing says
/// so until someone opens it expecting a starting point. That already happened
/// here once — the initial template shipped with the easing names spelled the
/// wrong way round, and the only test asserted that it drew, which it did, in
/// silence, as linear.
///
/// So the guard is not "it produced sprites". It is that the script the repo
/// offers as reference does what its own comments claim.
@Suite("Example scripts", .serialized)
struct ExampleScriptTests {
    /// `Examples/` sits at the repository root, outside the package, so it is
    /// reached by path rather than as a bundled resource: the target declares
    /// no resources, and adding some to reach one file would put the examples
    /// where SwiftPM indexes them.
    private static let examplesDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // StoryboardScriptingTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // the repository root
        .appendingPathComponent("Examples/scripts")

    private func run(_ name: String) throws -> ScriptRuntime.Outcome {
        let url = Self.examplesDirectory.appendingPathComponent(name)
        let source = try String(contentsOf: url, encoding: .utf8)

        return ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: 1,
        ))
    }

    @Test("wave-mesh runs clean")
    func waveMeshRuns() throws {
        let outcome = try run("wave-mesh.js")

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(!outcome.sprites.isEmpty)
    }

    /// The script's whole reason for existing is per-particle rules with access
    /// to the index: every dot takes its own phase and its own brightness from
    /// where it sits in the grid. If they all came out identical the example
    /// would be demonstrating nothing a parameter set could not have covered.
    @Test("every dot gets its own motion and its own brightness")
    func dotsDiffer() throws {
        let sprites = try run("wave-mesh.js").sprites
        #expect(sprites.count > 1)

        // One image, many rules — the point is not many images.
        #expect(Set(sprites.map(\.filePath)).count == 1)

        // The DISPLACEMENT from each dot's own base, not its absolute
        // position: the rows sit at different heights, so absolute `moveY`
        // values differ even when every dot rides an identical wave. Measuring
        // those would be measuring the layout and reporting it as the phase —
        // verified by flattening the phase and watching that version pass.
        let displacements = Set(sprites.map { sprite in
            sprite.commands.compactMap { command -> String? in
                guard case let .moveY(start, end) = command.payload else { return nil }
                let base = sprite.defaultY
                return String(format: "%.3f,%.3f", start - base, end - base)
            }.joined(separator: "|")
        })
        #expect(displacements.count > 1, "the dots ride one wave, in step")

        // Brightness is compared WITHIN one row, because the rows are dimmed
        // by perspective on top of it: across the whole grid the opacities
        // differ even with the slope term flattened, so the comparison would
        // be reading the depth cue and calling it the lighting. Verified by
        // replacing the slope with a constant and watching that version pass.
        let byRow = Dictionary(grouping: sprites, by: \.defaultY)
        let row = try #require(byRow.values.max(by: { $0.count < $1.count }))
        #expect(row.count > 1)

        let lit = Set(row.compactMap { sprite in
            sprite.commands.compactMap { command -> Double? in
                guard case let .fade(_, end) = command.payload else { return nil }
                return end
            }.max().map { String(format: "%.4f", $0) }
        })
        #expect(lit.count > 1, "one row is lit flat — the slope term is gone")
    }

    /// Declared controls are what let someone tune the example instead of
    /// reading it. A `params()` block that stopped parsing would leave the
    /// inspector empty with the script still drawing — declared and
    /// unreachable, which looks like the feature is there.
    @Test("wave-mesh declares its controls")
    func waveMeshDeclaresControls() throws {
        let declared = try #require(try run("wave-mesh.js").declared)
        let ids = Set(declared.map(\.id))

        #expect(ids.contains("columns"))
        #expect(ids.contains("amplitude"))
        #expect(ids.contains("tint"))
    }

    /// The script prints its own sprite count, so the log is a claim the run
    /// can be held to. A count that drifts from what was produced is the
    /// example describing something other than what it does.
    @Test("the printed count matches what was produced")
    func printedCountMatches() throws {
        let outcome = try run("wave-mesh.js")
        let line = try #require(outcome.logs.first?.message)
        let printed = try #require(Int(line.prefix(while: \.isNumber)))

        #expect(printed == outcome.sprites.count)
    }

    // ─── aurora ──────────────────────────────────────────────────────────────

    @Test("aurora runs clean")
    func auroraRuns() throws {
        let outcome = try run("aurora.js")

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(!outcome.sprites.isEmpty)
    }

    /// Additive is not decoration here: without it the columns occlude each
    /// other instead of summing, and a curtain of light becomes a row of bars.
    ///
    /// It also has to be **asked for correctly**. `additive` takes a span, and
    /// called with no arguments the bridge drops the command in silence —
    /// measured, 0 of 108 sprites were additive while the script read as
    /// though every one was.
    @Test("every column adds its light rather than covering its neighbour")
    func auroraIsAdditive() throws {
        let sprites = try run("aurora.js").sprites
        let states = StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites), at: 2000,
        )

        #expect(!states.isEmpty)
        // Counted rather than `allSatisfy(\.additive)`: a key path inside the
        // macro is read as possibly throwing, and the count says how many when
        // it fails.
        let plain = states.count { !$0.additive }
        #expect(plain == 0, "\(plain) of \(states.count) columns are not additive")
    }

    /// A curtain is fog, not bars.
    ///
    /// The complaint that drove the rewrite was hard vertical edges, and the
    /// answer is two sprites per piece: a `streak` for the shaft and a much
    /// wider `smoke` for the haze around it. The haze is what removes the
    /// edges, so its absence is the failure to guard against — and it was
    /// absent once already, when the layer declared `Image.smoke` and every
    /// sprite was built with `Image.streak` regardless.
    @Test("every shaft has haze around it")
    func auroraHasHaze() throws {
        let sprites = try run("aurora.js").sprites

        var byImage: [String: Int] = [:]
        for sprite in sprites { byImage[sprite.filePath, default: 0] += 1 }

        let shafts = byImage["__builtin__/streak.png"] ?? 0
        let haze = byImage["__builtin__/smoke.png"] ?? 0
        #expect(shafts > 0, "no shafts")
        #expect(haze == shafts, "\(haze) haze sprites for \(shafts) shafts")
    }

    /// And the haze is much wider than the shaft it softens, or it is a second
    /// bar rather than fog.
    @Test("the haze is wider than the shaft")
    func auroraHazeIsWide() throws {
        let sprites = try run("aurora.js").sprites
        let prepared = StoryboardResolver.prepare(sprites)
        let states = StoryboardResolver.resolve(prepared, at: 2000)

        var shaftWidth = 0.0
        var hazeWidth = 0.0
        for (index, state) in states.enumerated() where state.visible {
            let width = state.scaleX * 64
            if sprites[index].filePath.contains("smoke") {
                hazeWidth = max(hazeWidth, width)
            } else {
                shaftWidth = max(shaftWidth, width)
            }
        }

        #expect(shaftWidth > 0)
        #expect(hazeWidth > shaftWidth * 2, "haze \(Int(hazeWidth)) vs shaft \(Int(shaftWidth))")
    }

    /// The colour changes **along** a column, which is why a column is a stack
    /// of pieces rather than one tall sprite: a sprite carries one tint, so a
    /// gradient up a curtain has to be several. Green at the base going violet
    /// at the crown is the palette of the thing.
    @Test("the colour ramps along a column")
    func auroraColourRamps() throws {
        let sprites = try run("aurora.js").sprites

        var tints: Set<String> = []
        for sprite in sprites {
            for command in sprite.commands {
                if case let .color(startR, startG, startB, _, _, _) = command.payload {
                    tints.insert("\(Int(startR)),\(Int(startG)),\(Int(startB))")
                }
            }
        }
        #expect(tints.count >= 3, "\(tints.count) tints: a ramp needs at least three")
    }

    /// Columns are **not parallel**: they follow the tangent of the arc the
    /// curtain hangs in. Straight vertical columns read as a barcode however
    /// they ripple, which is exactly what the first version looked like.
    @Test("the columns fan along an arc rather than standing parallel")
    func auroraColumnsFan() throws {
        let sprites = try run("aurora.js").sprites
        let states = StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites), at: 2000,
        ).filter(\.visible)

        let angles = Set(states.map { Int($0.rotation * 100) })
        #expect(angles.count > 5, "\(angles.count) distinct angles: the curtain is flat")

        // And they lean both ways from the middle, which is what an arc does.
        let rotations = states.map(\.rotation)
        #expect(rotations.contains { $0 > 0.05 })
        #expect(rotations.contains { $0 < -0.05 })
    }

    /// The ripple travels **sideways**: neighbouring columns move together with
    /// a lag, which is what reads as cloth in a draught. Columns swaying in
    /// unison are a slab leaning over, and that is what a single shared wobble
    /// would give.
    @Test("the ripple travels along the curtain rather than moving it as one")
    func auroraRipplesSideways() throws {
        let sprites = try run("aurora.js").sprites
        let prepared = StoryboardResolver.prepare(sprites)

        // Two moments, and how far each column moved between them.
        let early = StoryboardResolver.resolve(prepared, at: 800)
        let later = StoryboardResolver.resolve(prepared, at: 2400)
        let shifts = zip(early, later).map { $1.x - $0.x }

        #expect(shifts.count > 8)
        // Neighbours differ — a shared wobble would move them all alike.
        // Counted against the *column* count rather than the sprite count:
        // each column is now six sprites — three pieces, each with its haze —
        // and every piece of one column shares its column's shift by design.
        let distinct = Set(shifts.map { Int($0 * 10) })
        #expect(distinct.count > 10, "\(distinct.count) distinct shifts: the sheet moves as one")
        // And some go one way while others go the other, which a leaning slab
        // cannot do.
        #expect(shifts.contains { $0 > 0.5 })
        #expect(shifts.contains { $0 < -0.5 })
    }

    /// Brightness ripples on its own period, so light appears and dies in place
    /// while the curtain drifts. Tied to the shape, the sheet reads as a solid
    /// object sliding about.
    @Test("columns light up at different times")
    func auroraBrightnessVaries() throws {
        let sprites = try run("aurora.js").sprites
        let states = StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites), at: 2000,
        ).filter(\.visible)

        let opacities = states.map(\.opacity)
        let spread = (opacities.max() ?? 0) - (opacities.min() ?? 0)
        #expect(spread > 0.01, "every column is at \(opacities.first ?? 0)")
        // None fully dark: a column that vanishes leaves a hole in the sheet.
        #expect(opacities.allSatisfy { $0 > 0 })
    }

    /// Commands written for something off the frame are commands nobody sees,
    /// and they still take up room in the file.
    @Test("the curtain stays on the stage")
    func auroraStaysOnStage() throws {
        let sprites = try run("aurora.js").sprites
        let states = StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites), at: 2000,
        ).filter(\.visible)

        // Measured at the original default width of 900, ten of forty-four
        // columns drew off-stage.
        let off = states.count { $0.x < -107 || $0.x > 747 }
        #expect(off == 0, "\(off) of \(states.count) columns are off the stage")
    }

    @Test("aurora declares its controls")
    func auroraDeclaresControls() throws {
        let declared = try #require(try run("aurora.js").declared)
        let ids = Set(declared.map(\.id))

        // The axes the effect is actually tuned on.
        // `bands` is gone with the rewrite: the colour ramps along a column
        // rather than between stacked sheets, so `tilt` and `haze` are the axes
        // that replaced it. `tilt` is the arc made visible — a column follows
        // the slope of the hem rather than standing vertical — and the guard
        // named it `arc` while the script declared `tilt`, so it asserted a
        // control that never existed.
        for id in ["columns", "tilt", "haze", "sway", "ripples", "speed", "segments"] {
            #expect(ids.contains(id), "missing \(id)")
        }
    }
}
