import Foundation
import Testing

@testable import StoryboardCore

/// Every sprite a clip draws belongs to it, filters' sprites included.
///
/// Reported: Chromatic on a text clip left it with no selection frame. A
/// filter names what it adds after its own id — `chromatic-1a2b3c4d/cR-0` —
/// and the frame, the drag preview and everything else that asks "is this
/// sprite the clip's?" go by the clip's id. With Keep Original off, Chromatic
/// replaces every sprite, so none were left to measure. Shatter and Slice
/// Glitch replace theirs the same way.
@Suite("Filter sprites belong to their clip")
struct FilterSpriteOwnershipTests {
    private func clip(with filters: [FilterDescriptor], values: [String: EffectValue] = [:]) -> (EffectNode, [StoryboardSprite]) {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text("hola")
        node.filters = filters.enumerated().map { index, filter in
            FilterNode(
                id: "\(filter.type)-\(index)", type: filter.type,
                values: filter.defaultValues.merging(values) { _, new in new },
            )
        }
        return (node, EffectEvaluator().evaluate(node))
    }

    @Test("Chromatic without the original still leaves the clip sprites to frame")
    func chromaticReplacing() {
        let (node, sprites) = clip(with: [ChromaticFilter.descriptor], values: [ChromaticFilter.Param.keepsOriginal: .toggle(false)])
        #expect(!sprites.isEmpty)
        #expect(sprites.allSatisfy { ClipBounds.sprite($0.id, belongsTo: node.id) })
    }

    @Test("every filter's sprites belong to the clip", arguments: FilterLibrary.standard.descriptors.map(\.type))
    func everyFilter(_ type: String) throws {
        let filter = try #require(FilterLibrary.standard.descriptors.first { $0.type == type })
        let (node, sprites) = clip(with: [filter])
        let strays = sprites.filter { !ClipBounds.sprite($0.id, belongsTo: node.id) }.map(\.id)
        #expect(strays.isEmpty, "\(type): \(strays.prefix(3))")
    }

    @Test("two filters' sprites stay apart once re-homed")
    func idsStayUnique() {
        let (_, sprites) = clip(with: [GlowFilter.descriptor, EchoFilter.descriptor])
        #expect(Set(sprites.map(\.id)).count == sprites.count)
    }
}
