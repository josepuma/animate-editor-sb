import Foundation
import Testing

@testable import StoryboardCore

/// Which category each shipped filter lives in.
@Suite("Filter category mapping")
struct FilterCategoryMappingTests {
    /// The user-approved table. Written out in full rather than derived: a
    /// test that read the mapping from the descriptors would agree with any
    /// mapping at all.
    private static let table: [FilterCategory: Set<String>] = [
        .look: ["Tint", "Blur", "LED", "Outline", "Hue Cycle", "Halftone", "Duotone", "Ink"],
        .light: ["Glow", "Shadow", "Lens Flare"],
        .motion: ["Wiggle", "Motion Path", "Inertial Bounce", "Squash & Stretch", "Turbulence", "Vortex", "Attractor"],
        .threeD: ["Card Flip", "Carousel", "Extrude"],
        .repetition: ["Grid", "Radial Repeat", "Mirror", "Echo"],
        .destroy: ["Chromatic", "Shatter", "Slice Glitch", "Disintegrate", "Spark Trail", "Impact Ring"],
        .time: ["Time", "Ease", "Fade", "Loop", "Stagger", "Posterize Time"],
        .audio: ["Audio Drive", "Beat Pulse"],
    ]

    private static var grouped: [FilterCategory: Set<String>] {
        Dictionary(
            grouping: FilterLibrary.standard.descriptors,
            by: \.category,
        ).mapValues { Set($0.map(\.name)) }
    }

    @Test("The library has the thirty-nine filters the table names")
    func count() {
        #expect(FilterLibrary.standard.descriptors.count == 39)
        #expect(Self.table.values.reduce(0) { $0 + $1.count } == 39)
    }

    @Test("Every filter sits in exactly the category the table gives it")
    func mapping() {
        for category in FilterCategory.allCases {
            #expect(
                Self.grouped[category, default: []] == Self.table[category],
                "\(category.rawValue)",
            )
        }
    }

    @Test("Descriptors come out in category order, stable by name inside one")
    func sorted() {
        let descriptors = FilterLibrary.standard.descriptors
        let order = descriptors.map(\.category.order)
        #expect(order == order.sorted())
        for category in FilterCategory.allCases {
            let names = descriptors.filter { $0.category == category }.map(\.name)
            #expect(names == names.sorted(), "\(category.rawValue)")
        }
    }

    @Test("A saved filter names its type only — the category is derived, never stored")
    func persistenceUnchanged() throws {
        let node = FilterNode(id: "glow-1", type: "glow")
        let data = try JSONEncoder().encode(node)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Exactly the keys a project saved before categories existed has, so
        // opening one and saving it again rewrites nothing.
        #expect(Set(object.keys) == ["id", "type", "isEnabled", "values"])
        #expect(try JSONDecoder().decode(FilterNode.self, from: data) == node)
    }
}
