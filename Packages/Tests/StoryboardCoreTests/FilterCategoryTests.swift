import Foundation
import Testing

@testable import StoryboardCore

/// How the Filters tab is grouped: by what a filter does to a clip.
@Suite("Filter categories")
struct FilterCategoryTests {
    @Test("The declared order is the order the panel shows")
    func displayOrder() {
        #expect(FilterCategory.displayOrder == [
            .look, .light, .motion, .threeD, .repetition, .destroy, .time, .audio,
        ])
        #expect(FilterCategory.displayOrder.map(\.rawValue) == [
            "Look", "Light", "Motion", "3D", "Repeat", "Destroy", "Time", "Audio",
        ])
    }

    @Test("Every case is ordered, so none can be added and forgotten")
    func everyCaseIsOrdered() {
        #expect(Set(FilterCategory.displayOrder) == Set(FilterCategory.allCases))
        #expect(FilterCategory.displayOrder.count == FilterCategory.allCases.count)
    }

    @Test("Both category enums share one ordering rule")
    func sharedOrdering() {
        #expect(FilterCategory.precedes((.look, "Z"), (.light, "A")))
        #expect(!FilterCategory.precedes((.light, "A"), (.look, "Z")))
        #expect(FilterCategory.precedes((.look, "A"), (.look, "B")))
        #expect(LibraryCategory.precedes((.generate, "Z"), (.audio, "A")))
        #expect(LibraryCategory.precedes((.audio, "A"), (.audio, "B")))
        #expect(!LibraryCategory.precedes((.audio, "B"), (.audio, "A")))
    }
}
