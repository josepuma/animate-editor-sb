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
}
