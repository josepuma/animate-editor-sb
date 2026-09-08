import Foundation
import LanguageSupport
import Testing

@testable import ScriptEditorFeature

/// What a name is, answered where the cursor is resting.
///
/// Completion answers "what can I write here"; this answers "what is this
/// thing", which is the question somebody has most of the time — code is read
/// far more than it is typed.
@Suite("Hover")
struct HoverTests {
    private struct NoLocations: LocationService {
        func length(of _: Int) -> Int? { nil }
        func textLocation(from _: Int) -> Result<TextLocation, Error> {
            .success(TextLocation(zeroBasedLine: 0, column: 0))
        }
        func location(from _: TextLocation) -> Result<Int, Error> { .success(0) }
    }

    /// Hovers `source` at the given offset and says whether anything answered.
    private func hasInfo(_ source: String, at location: Int) async throws -> Bool {
        let service = ScriptLanguageService()
        try await service.openDocument(with: source, locationService: NoLocations())
        return try await service.info(at: location) != nil
    }

    // MARK: - Reading the word

    /// The cursor sits *inside* a word, not at its end — so the reader has to
    /// look both ways, unlike the completion context.
    @Test("a word is found from the middle of it", arguments: [0, 2, 5, 6])
    func wordFromTheMiddle(offset: Int) {
        let found = CompletionContext.word(at: offset, in: "sprite(Image.soft)")

        #expect(found?.word == "sprite")
        #expect(found?.range == NSRange(location: 0, length: 6))
    }

    @Test("a member is found with its receiver")
    func memberWithReceiver() throws {
        let source = "sprite(Image.soft)"
        let found = try #require(CompletionContext.word(at: 15, in: source))

        #expect(found.word == "soft")
        #expect(CompletionContext.receiver(before: found.range, in: source) == "Image")
    }

    /// A word with no dot before it has no receiver.
    @Test("a bare word has no receiver")
    func bareWordHasNoReceiver() throws {
        let source = "const count = 24"
        let found = try #require(CompletionContext.word(at: 8, in: source))

        #expect(CompletionContext.receiver(before: found.range, in: source) == nil)
    }

    @Test("whitespace is not a word")
    func whitespaceIsNotAWord() {
        #expect(CompletionContext.word(at: 6, in: "const  count") == nil)
    }

    // MARK: - What answers

    @Test("a global is described")
    func globalDescribed() async throws {
        #expect(try await hasInfo("sprite(Image.soft)", at: 2))
        #expect(try await hasInfo("const d = duration", at: 12))
    }

    /// The receiver is what makes this work: `soft` is not a global.
    @Test("a member is described through its receiver")
    func memberDescribed() async throws {
        #expect(try await hasInfo("sprite(Image.soft)", at: 15))
        #expect(try await hasInfo("  .move(Ease.quadOut, 0, 1, 0, 0, 1, 1)", at: 16))
    }

    @Test("a sprite method is described")
    func methodDescribed() async throws {
        #expect(try await hasInfo("sprite(Image.soft).fade(0, 1, 0, 1)", at: 21))
    }

    /// A name the table does not know says nothing, rather than guessing.
    @Test("an unknown name is not described", arguments: [
        ("const myOwnThing = 1", 8),
        ("sprite(Image.nonsense)", 16),
    ])
    func unknownNotDescribed(source: String, offset: Int) async throws {
        #expect(try await hasInfo(source, at: offset) == false)
    }

    /// A member name looked up without its receiver would miss.
    ///
    /// `soft` is not in the globals, so an implementation that ignored the
    /// receiver would describe `sprite` and nothing else — which is the shape
    /// of bug that looks like "hover works sometimes".
    @Test("a member is not confused for a global")
    func memberIsNotAGlobal() async throws {
        // `out` is an easing, and also not a global.
        #expect(try await hasInfo("  .move(Ease.out, 0, 1, 0, 0, 1, 1)", at: 14))
        #expect(try await hasInfo("const out = 1", at: 7) == false)
    }

    /// An out-of-range offset must not trap.
    @Test("an out-of-range offset is refused")
    func outOfRange() async throws {
        #expect(try await hasInfo("short", at: 9999) == false)
    }
}
