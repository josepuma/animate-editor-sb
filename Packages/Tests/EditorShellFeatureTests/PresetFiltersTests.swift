import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// A preset that brings filters: placed with them, swapped without touching
/// them.
@Suite("Presets with filters", .serialized)
@MainActor
struct PresetFiltersTests {
    private func preset(_ id: String) throws -> EffectPreset {
        try #require(EditorShellModel().presets.first { $0.id == id }, "the shell does not offer \(id)")
    }

    /// Placed, the filters arrive — each with an id of this clip's own. The id
    /// prefixes the sprites a filter derives, so two clips sharing one would
    /// name the same sprites and collapse onto each other.
    @Test("placing a preset brings its filters, each with a fresh id")
    func placingBringsFilters() throws {
        let shell = EditorShellModel()
        let ring = try preset("pulse-ring")

        let first = try #require(shell.addPreset(ring, at: 0))
        let second = try #require(shell.addPreset(ring, at: 3000))

        let a = try #require(shell.effects[first.id]).filters
        let b = try #require(shell.effects[second.id]).filters
        #expect(a.map(\.type) == ring.filters.map(\.type))
        #expect(Set(a.map(\.id)).isDisjoint(with: b.map(\.id)))
    }

    /// Swapping a preset keeps what makes the clip itself, and the filters an
    /// author tuned are part of that.
    @Test("swapping a preset leaves the clip's filters alone")
    func swapKeepsFilters() throws {
        let shell = EditorShellModel()
        let placed = try #require(shell.addPreset(try preset("pulse-ring"), at: 0))
        let before = try #require(shell.effects[placed.id]).filters

        shell.applyPreset(try preset("shape-circle"), to: placed.id)

        let after = try #require(shell.effects[placed.id]).filters
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.map(\.values) == before.map(\.values))
    }

    @Test("the audio bars presets are on offer")
    func barsPresetsOffered() throws {
        _ = try preset("circular-spectrum")
    }
}
