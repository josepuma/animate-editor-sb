import LanguageSupport
import Testing

@testable import ScriptEditorFeature

/// What the editor is offered, given what has been typed.
@Suite("Completions")
struct CompletionTests {
    /// Opens a document and asks for completions at its end, which is where a
    /// cursor is while somebody types.
    private func completions(after source: String) async throws -> [String] {
        let service = ScriptLanguageService()
        try await service.openDocument(with: source, locationService: NoLocations())

        let result = try await service.completions(at: source.utf16.count, reason: .standard)
        return result.items.map(\.filterText)
    }

    // MARK: - Namespaces

    @Test("after Image. the built-in images are offered")
    func imagesOffered() async throws {
        let names = try await completions(after: "sprite(Image.")

        #expect(names == ScriptAPI.images.map(\.name))
        #expect(names.contains("soft"))
    }

    @Test("after Ease. every curve is offered")
    func easingsOffered() async throws {
        let names = try await completions(after: "  .move(Ease.")

        #expect(names.count == 35, "the format has 35 curves; got \(names.count)")
        #expect(names.contains("outQuad"))
    }

    @Test("a partial member narrows the list")
    func partialNarrows() async throws {
        let names = try await completions(after: "sprite(Image.s")

        #expect(names == ["soft", "smoke", "star", "square", "streak"])
    }

    /// Matched on the start, not anywhere in the name.
    ///
    /// A substring match on "in" would offer half the easing table, which is a
    /// list where the answer is buried.
    @Test("matching is by prefix, not substring")
    func prefixNotSubstring() async throws {
        let names = try await completions(after: "  .move(Ease.out")

        #expect(names.allSatisfy { $0.hasPrefix("out") })
        #expect(!names.contains("inOutQuad"), "a substring match would have included this")
    }

    @Test("matching ignores case")
    func caseInsensitive() async throws {
        #expect(try await completions(after: "sprite(Image.SO").contains("soft"))
    }

    // MARK: - Chained calls

    @Test("after a sprite, its methods are offered")
    func spriteMethodsOffered() async throws {
        let names = try await completions(after: "sprite(Image.soft).")

        #expect(names == ScriptAPI.spriteMethods.map(\.name))
    }

    /// The way a chain is actually written.
    @Test("a multi-line chain still offers methods")
    func multiLineChain() async throws {
        let names = try await completions(after: "sprite(Image.soft)\n  .fade(0, 100, 0, 1)\n  .")

        #expect(names.contains("move"))
    }

    // MARK: - Globals

    @Test("a partial global is completed")
    func partialGlobal() async throws {
        #expect(try await completions(after: "const s = spr").contains("sprite"))
    }

    /// Nothing on an empty position.
    ///
    /// Every global offered on an empty line is a popup that appears while
    /// somebody is thinking, and the only way past it is to type through it.
    @Test("an empty position offers nothing")
    func emptyOffersNothing() async throws {
        #expect(try await completions(after: "const s = ").isEmpty)
    }

    // MARK: - Where nothing belongs

    @Test("nothing is offered inside a string or comment", arguments: [
        #"sprite("sb/"#,
        "// a note about Image.",
    ])
    func nothingInStringsOrComments(source: String) async throws {
        #expect(try await completions(after: source).isEmpty)
    }

    // MARK: - Insertion

    /// Choosing a completion must replace what was typed, not append to it.
    @Test("a partial word is replaced, not appended to")
    func partialIsReplaced() async throws {
        let service = ScriptLanguageService()
        let source = "sprite(Image.so"
        try await service.openDocument(with: source, locationService: NoLocations())

        let result = try await service.completions(at: source.utf16.count, reason: .standard)
        let soft = try #require(result.items.first { $0.filterText == "soft" })
        let range = try #require(soft.insertRange, "without a range, choosing this writes Image.sosoft")

        #expect(range.length == 2, "it must replace the two characters typed")
        #expect(range.location == source.utf16.count - 2)
    }

    /// Anything callable arrives with its opening paren.
    @Test("callables insert their paren")
    func callablesInsertParen() async throws {
        let service = ScriptLanguageService()
        let source = "sprite(Image.soft)."
        try await service.openDocument(with: source, locationService: NoLocations())

        let result = try await service.completions(at: source.utf16.count, reason: .standard)
        let move = try #require(result.items.first { $0.filterText == "move" })

        #expect(move.insertText == "move(")
    }

    /// One item is preselected, so Return works without arrowing down first.
    @Test("exactly one item is selected")
    func oneSelected() async throws {
        let service = ScriptLanguageService()
        let source = "sprite(Image."
        try await service.openDocument(with: source, locationService: NoLocations())

        let result = try await service.completions(at: source.utf16.count, reason: .standard)

        #expect(result.items.filter(\.selected).count == 1)
    }

    // MARK: - Document tracking

    /// The service is told about edits rather than re-reading, so an edit it
    /// mishandles shows up as completions for the wrong text.
    @Test("an edit reaches the tracked document")
    func editIsTracked() async throws {
        let service = ScriptLanguageService()
        try await service.openDocument(with: "sprite(Image.", locationService: NoLocations())

        // Typing "s" at the end.
        try await service.documentDidChange(
            position: 13, changeInLength: 1, lineChange: 0, columnChange: 1, newText: "s",
        )

        let result = try await service.completions(at: 14, reason: .standard)

        #expect(result.items.allSatisfy { $0.filterText.hasPrefix("s") })
        #expect(!result.items.isEmpty)
    }
}

/// A location service that knows nothing.
///
/// Completion reads the document text and a UTF-16 offset, which is all the
/// editor gives it — nothing here converts between lines and offsets, so a stub
/// is honest rather than lazy.
private struct NoLocations: LocationService {
    func length(of _: Int) -> Int? { nil }

    func textLocation(from _: Int) -> Result<TextLocation, Error> {
        .success(TextLocation(zeroBasedLine: 0, column: 0))
    }

    func location(from _: TextLocation) -> Result<Int, Error> {
        .success(0)
    }
}
