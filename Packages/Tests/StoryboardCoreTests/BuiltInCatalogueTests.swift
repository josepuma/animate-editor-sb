import Foundation
import Testing

@testable import StoryboardCore

/// The one list of built-in images the picker reads.
@Suite("Built-in catalogue")
struct BuiltInCatalogueTests {
    /// The guard this exists for. The hand-written menu it replaced had lost
    /// 15 of 62 built-ins — the Flat vocabulary, the beams, three slashes —
    /// which presets drew and nobody could pick. A built-in that exists has
    /// to be in the catalogue, and the catalogue names nothing else.
    @Test("the catalogue lists exactly the built-ins")
    func coversEveryBuiltIn() {
        let listed = BuiltInSprite.catalogue.map(\.path)
        #expect(Set(listed) == Set(BuiltInSprite.all))
        #expect(listed.count == Set(listed).count, "a built-in is listed twice")
    }

    @Test("every entry has a name, and no two share one")
    func namesAreUnique() {
        let titles = BuiltInSprite.catalogue.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(titles.count == Set(titles).count, "two sprites share a name")
    }

    @Test("every group has something in it", arguments: BuiltInSprite.Group.allCases)
    func groupsAreUsed(group: BuiltInSprite.Group) {
        #expect(BuiltInSprite.catalogue.contains { $0.group == group })
    }

    @Test("a group shows only its own entries, in catalogue order")
    func groupFilters() {
        let fire = BuiltInSprite.entries(matching: "", in: .fire)
        #expect(!fire.isEmpty && fire.allSatisfy { $0.group == .fire })
        #expect(fire == BuiltInSprite.catalogue.filter { $0.group == .fire })
        #expect(BuiltInSprite.entries(matching: "", in: nil) == BuiltInSprite.catalogue)
    }

    /// A search is for a name already known, wherever it lives — so it reads
    /// past the chosen group, and matches a group's name as well as a title.
    @Test("a search reads titles and group names, past the chosen group")
    func searchMatches() {
        let bolts = BuiltInSprite.entries(matching: "BOLT", in: .nature)
        #expect(Set(bolts.map(\.title)) == ["Bolt", "Bolt Thin"])
        let hud = BuiltInSprite.entries(matching: "hud", in: nil)
        #expect(hud.count == BuiltInSprite.hudShapes.count)
        #expect(BuiltInSprite.entries(matching: "zzz", in: nil).isEmpty)
    }

    @Test("an entry is found by its path")
    func lookup() {
        #expect(BuiltInSprite.entry(for: BuiltInSprite.strobe)?.title == "Spotlight")
        #expect(BuiltInSprite.entry(for: "sb/my-own.png") == nil)
        #expect(BuiltInSprite.entry(for: "") == nil)
    }
}
