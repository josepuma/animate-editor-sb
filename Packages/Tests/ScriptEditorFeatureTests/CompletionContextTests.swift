import Testing

@testable import ScriptEditorFeature

/// Reading what the author is in the middle of typing.
///
/// This is the part that decides whether completion helps or gets in the way,
/// so it is tested as pure text in and an answer out — no editor involved.
@Suite("Completion context")
struct CompletionContextTests {
    /// Reads the context at the end of `source`, which is where a cursor is
    /// while somebody types.
    private func context(after source: String) -> CompletionContext {
        CompletionContext.at(source.utf16.count, in: source)
    }

    // MARK: - Namespaces

    @Test("after a namespace dot, its members are wanted", arguments: [
        ("sprite(Image.", "Image"),
        ("  .move(Ease.", "Ease"),
        ("rng.", "rng"),
        ("console.", "console"),
        ("{ layer: Layer.", "Layer"),
        ("{ origin: Origin.", "Origin"),
    ])
    func namespaceMembers(source: String, namespace: String) {
        #expect(context(after: source) == .members(of: namespace, prefix: ""))
    }

    /// Partially typed, so the list narrows rather than starting over.
    @Test("a partial member keeps what was typed")
    func partialMember() {
        #expect(context(after: "sprite(Image.so") == .members(of: "Image", prefix: "so"))
    }

    /// An unknown receiver is not a namespace, so nothing is offered.
    @Test("an unknown namespace offers nothing")
    func unknownNamespace() {
        #expect(context(after: "somethingElse.") == .none)
    }

    // MARK: - Chained calls

    /// The case that matters most: a sprite mid-chain.
    @Test("after a closing paren, sprite methods are wanted", arguments: [
        "sprite(Image.soft).",
        "sprite(Image.soft).fade(0, 100, 0, 1).",
        "sprite(Image.soft)\n  .move(0, 900, 0, 0, 10, 10)\n  .",
    ])
    func spriteMethods(source: String) {
        #expect(context(after: source) == .spriteMethod(prefix: ""))
    }

    @Test("a partial method keeps what was typed")
    func partialMethod() {
        #expect(context(after: "sprite(Image.soft).fa") == .spriteMethod(prefix: "fa"))
    }

    // MARK: - Globals

    @Test("a bare word wants globals")
    func bareWord() {
        #expect(context(after: "const x = spr") == .global(prefix: "spr"))
    }

    /// With nothing typed, the list is how somebody finds out what exists.
    @Test("an empty position wants globals")
    func emptyPosition() {
        #expect(context(after: "const x = ") == .global(prefix: ""))
        #expect(context(after: "") == .global(prefix: ""))
    }

    // MARK: - Where nothing should be offered

    /// A popup inside a file path covers the thing being typed, and has nothing
    /// in it that could ever be right.
    @Test("nothing is offered inside a string", arguments: [
        #"sprite("sb/"#,
        "sprite('sb/back",
        "const s = `hello ",
    ])
    func insideAString(source: String) {
        #expect(context(after: source) == .none)
    }

    @Test("nothing is offered inside a comment", arguments: [
        "// this is a note about spr",
        "const x = 1 // and Image.",
    ])
    func insideAComment(source: String) {
        #expect(context(after: source) == .none)
    }

    /// A string that closed on the same line is not still open.
    @Test("a closed string does not swallow the rest of the line")
    func closedString() {
        #expect(context(after: #"sprite("sb/a.png")."#) == .spriteMethod(prefix: ""))
    }

    /// An escaped quote does not close the string.
    @Test("an escaped quote keeps the string open")
    func escapedQuote() {
        #expect(context(after: #"sprite("it\" "#) == .none)
    }

    /// A comment on an earlier line does not affect this one.
    @Test("a comment on a previous line does not leak")
    func commentDoesNotLeak() {
        #expect(context(after: "// a note\nsprite(Image.") == .members(of: "Image", prefix: ""))
    }

    // MARK: - Out of bounds

    /// The editor reports UTF-16 offsets, and a stale one must not crash.
    @Test("an out-of-range location is refused rather than trapped")
    func outOfRange() {
        #expect(CompletionContext.at(9999, in: "short") == .none)
        #expect(CompletionContext.at(-1, in: "short") == .none)
    }

    /// A location inside a multi-byte character must not trap either.
    @Test("text with wide characters does not trap")
    func wideCharacters() {
        let source = "// 日本語のコメント\nsprite(Image."
        #expect(context(after: source) == .members(of: "Image", prefix: ""))
    }
}
