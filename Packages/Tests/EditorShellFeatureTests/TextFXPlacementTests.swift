import Foundation
import Testing

@testable import EditorShellFeature
@testable import StoryboardCore

/// The Text FX presets placed through the editor, not through a test's own
/// copy of the placement: the delay and the filter keyframes have to survive
/// `addPreset` itself.
@Suite("Text FX placement", .serialized)
@MainActor
struct TextFXPlacementTests {
    private func preset(_ id: String) throws -> EffectPreset {
        try #require(EditorShellModel().presets.first { $0.id == id }, "the shell does not offer \(id)")
    }

    @Test("a compound's layers keep the delay their preset gave them")
    func layersKeepDelay() throws {
        let shell = EditorShellModel()
        let impact = try preset("impact-title")
        let placed = try #require(shell.addPreset(impact, at: 0))
        let layers = try #require(shell.effects[placed.id]).layers
        #expect(layers.map(\.delay) == impact.layers.map { $0.delay > 0 ? $0.delay : nil })
        #expect(layers.allSatisfy { $0.delay != nil })
    }

    @Test("a layer with no delay is placed without one")
    func noDelayStaysUnset() throws {
        let shell = EditorShellModel()
        let placed = try #require(shell.addPreset(try preset("lyric-sparkle"), at: 0))
        let layers = try #require(shell.effects[placed.id]).layers
        #expect(!layers.isEmpty)
        #expect(layers.allSatisfy { $0.delay == nil })
    }

    @Test("a filter's keyframes come along with it")
    func filterKeyframes() throws {
        let shell = EditorShellModel()
        let placed = try #require(shell.addPreset(try preset("focus-in"), at: 0))
        let blur = try #require(shell.effects[placed.id]?.filters.first { $0.type == BlurFilter.descriptor.type })
        #expect(blur.isAnimated)
    }
}
