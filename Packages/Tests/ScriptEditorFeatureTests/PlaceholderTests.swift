import Testing
@testable import ScriptEditorFeature

@Suite("Script editor feature")
struct PlaceholderTests {
    @Test("the target builds")
    func targetBuilds() { #expect(Bool(true)) }
}
