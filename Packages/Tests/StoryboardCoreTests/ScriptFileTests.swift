import Foundation
import Testing

@testable import StoryboardCore

/// `ScriptFile` narrows a script's on-disk reference to a single path
/// component — no separators, no `..`, no leading dot — so a traversal is
/// unrepresentable in memory rather than merely rejected by a check someone
/// remembers to call.
@Suite("ScriptFile")
struct ScriptFileTests {
    // MARK: - Rejection

    @Test("rejects unsafe names", arguments: [
        "",
        ".",
        "..",
        "a/b",
        "a\\b",
        "../x",
        ".hidden",
        String(repeating: "a", count: 300),
        "a\u{0}b",
    ])
    func rejectsUnsafeNames(name: String) {
        #expect(ScriptFile(name: name) == nil)
    }

    // MARK: - Acceptance

    @Test("accepts ordinary names", arguments: [
        "wave",
        "my-script",
        "a_1",
    ])
    func acceptsOrdinaryNames(name: String) {
        #expect(ScriptFile(name: name) != nil)
    }

    // MARK: - fileName

    @Test("fileName appends .js exactly once")
    func fileNameAppendsExtensionOnce() throws {
        let file = try #require(ScriptFile(name: "wave"))
        #expect(file.fileName == "wave.js")
    }

    /// A name that already looks like it carries the extension must not have
    /// it stored twice — `name` itself never holds `.js`, so a caller cannot
    /// construct a reference that stacks the suffix.
    @Test("a name already ending in .js is not doubled")
    func nameEndingInExtensionIsNotDoubled() throws {
        let file = try #require(ScriptFile(name: "x.js"))
        #expect(!file.fileName.hasSuffix(".js.js"))
    }
}
