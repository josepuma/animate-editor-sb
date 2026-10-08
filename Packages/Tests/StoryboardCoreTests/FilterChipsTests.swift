import Foundation
import Testing

@testable import StoryboardCore

/// What the Filters tab lists: the chip row and the cards under it.
@Suite("Filter chips")
struct FilterChipsTests {
    private let library = FilterLibrary.standard.descriptors

    /// Every category has filters now; that an empty one is hidden is held
    /// by the narrowed-library case below, which shows Light alone.
    @Test("Chips are the non-empty categories in declared order")
    func chips() {
        #expect(FilterCategory.visibleChips(in: library) == [
            .look, .light, .motion, .threeD, .repetition, .destroy, .time, .audio,
        ])
    }

    @Test("Chips come from the whole library, so they do not jump while typing")
    func chipsIgnoreTheQuery() {
        let narrowed = library.filter { $0.name == "Glow" }
        // The function takes the library, not a result: handing it a narrowed
        // list is how a caller would get a different row, which is the bug.
        #expect(FilterCategory.visibleChips(in: narrowed) == [.light])
        #expect(FilterCategory.visibleChips(in: library).count == 8)
    }

    @Test("A chip lists only its own category")
    func chipFilters() {
        let shown = FilterCategory.visible(in: library, chip: .light, query: "")
        #expect(Set(shown.map(\.name)) == ["Glow", "Shadow", "Lens Flare"])
    }

    @Test("No chip and no query lists everything")
    func allChip() {
        #expect(FilterCategory.visible(in: library, chip: nil, query: "").count == 39)
    }

    @Test("A query overrides the chip, so searching never dead-ends")
    func queryOverridesChip() {
        let shown = FilterCategory.visible(in: library, chip: .look, query: "glow")
        #expect(shown.map(\.name) == ["Glow"])
    }

    @Test("A query also matches the category's name")
    func queryMatchesCategory() {
        let shown = FilterCategory.visible(in: library, chip: .look, query: "destroy")
        #expect(Set(shown.map(\.name)) == ["Chromatic", "Shatter", "Slice Glitch", "Disintegrate", "Spark Trail", "Impact Ring"])
    }

    @Test("Clearing the query gives the chip back")
    func clearedQuery() {
        let shown = FilterCategory.visible(in: library, chip: .time, query: "")
        #expect(Set(shown.map(\.name)) == ["Time", "Ease", "Fade", "Loop", "Stagger", "Posterize Time"])
    }
}
