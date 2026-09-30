import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// `Image.strobe` — the spotlight cone as a script sees it.
///
/// Before this the table held only the drawn shapes; the shipped textures were
/// reachable from the inspector's menu but not from code. A name that is not in
/// the table is `undefined`, and the bridge rejects it — so the test runs a
/// real script instead of reading the dictionary.
@Suite("Image.strobe", .serialized)
struct StrobeImageTests {
    @Test("a script can draw the spotlight by name")
    func scriptResolvesTheName() {
        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: "sprite(Image.strobe, Layer.Foreground, Origin.TopCentre, 320, 0)",
            values: [:], duration: 4000, seed: 1,
        ))

        #expect(outcome.diagnostics.isEmpty, "\(outcome.diagnostics)")
        #expect(outcome.sprites.first?.filePath == BuiltInSprite.strobe)
        #expect(outcome.sprites.count == 1)
    }

    @Test("the generated declarations offer it")
    func declarationsOfferIt() {
        #expect(ImageConstants.table["strobe"] == BuiltInSprite.strobe)
        #expect(TypeDeclarations.text.contains("readonly strobe:"))
    }
}
