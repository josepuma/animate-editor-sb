import Testing

@testable import StoryboardScripting

/// Replaced as the runtime lands; a target with no tests is a target SwiftPM
/// will not build.
@Suite("Scripting target")
struct PlaceholderTests {
    @Test("the target builds")
    func targetBuilds() {
        #expect(Bool(true))
    }
}
