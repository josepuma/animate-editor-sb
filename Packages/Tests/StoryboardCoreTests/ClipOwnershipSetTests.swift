import Testing

@testable import StoryboardCore

/// A group selection asks the same question as a single one, once per sprite
/// per frame — so it has to agree with `sprite(_:belongsTo:)` exactly, both
/// for a handful of clips and for a select-all.
@Suite("Clip ownership by set")
struct ClipOwnershipSetTests {
    private let sprites = [
        "node-a", "node-a/0", "node-a/L0/3", "node-ab/1", "node-b/glow-1/0", "other",
    ]

    @Test("agrees with the single test", arguments: [2, 40])
    func agreesWithSingle(groupSize: Int) {
        // Padded with ids nothing matches, to push past the small-set path.
        let padding = (0..<groupSize).map { "unused-\($0)" }
        let group = Set(["node-a", "node-b"] + padding)

        for sprite in sprites {
            let expected = group.contains { ClipBounds.sprite(sprite, belongsTo: $0) }
            #expect(
                ClipBounds.sprite(sprite, belongsToAnyOf: group) == expected,
                "\(sprite) with \(group.count) clips",
            )
        }
    }

    /// The separator is what keeps a clip from claiming a neighbour whose id
    /// it prefixes.
    @Test("a prefix of another id does not claim it", arguments: [1, 40])
    func prefixIsNotOwnership(groupSize: Int) {
        let group = Set(["node-a"] + (0..<groupSize).map { "unused-\($0)" })
        #expect(!ClipBounds.sprite("node-ab/1", belongsToAnyOf: group))
    }

    @Test("an empty set owns nothing")
    func emptyOwnsNothing() {
        #expect(!ClipBounds.sprite("node-a/0", belongsToAnyOf: []))
    }
}

/// The canvas asks the other way round: not "is this sprite one of these
/// clips'", but "whose is it".
@Suite("Clip owner of a sprite")
struct ClipOwnerTests {
    private let clips: Set<String> = ["node-a", "node-b"]

    @Test("a sprite, a layer's sprite and a filter's copy all find their clip")
    func findsOwner() {
        #expect(ClipBounds.owner(of: "node-a", among: clips) == "node-a")
        #expect(ClipBounds.owner(of: "node-a/0", among: clips) == "node-a")
        #expect(ClipBounds.owner(of: "node-b/L0/3", among: clips) == "node-b")
    }

    /// The separator is what keeps a clip from claiming a neighbour whose id
    /// it prefixes.
    @Test("a prefix of another id is not its owner")
    func prefixIsNotOwner() {
        #expect(ClipBounds.owner(of: "node-ab/1", among: clips) == nil)
    }

    @Test("a sprite no listed clip drew has no owner")
    func strangerHasNone() {
        #expect(ClipBounds.owner(of: "sb/bg.jpg", among: clips) == nil)
    }
}
