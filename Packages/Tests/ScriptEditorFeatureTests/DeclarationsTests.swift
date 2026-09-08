import Foundation
import Testing

@testable import ScriptEditorFeature

/// The names the script itself introduced.
///
/// Completion knew the host's API and nothing about the code in front of it, so
/// `count` — declared on the line above — was not offered while `duration` was.
@Suite("Script declarations")
struct DeclarationsTests {
    private func names(in source: String) -> [String] {
        ScriptDeclarations.all(in: source).map(\.name)
    }

    @Test("each declaration keyword is found", arguments: [
        ("const count = 24", "count"),
        ("let cursor = 0", "cursor"),
        ("var total = 1", "total"),
        ("function place(x) {}", "place"),
    ])
    func keywordsAreFound(source: String, expected: String) {
        #expect(names(in: source) == [expected])
    }

    /// The loop variable, which is the name used most inside the body.
    @Test("a for-loop variable is found")
    func loopVariable() {
        #expect(names(in: "for (let i = 0; i < count; i++) {").contains("i"))
    }

    @Test("indentation does not hide a declaration")
    func indented() {
        #expect(names(in: "  const angle = 0").contains("angle"))
    }

    /// Sorted, so the list does not reorder between keystrokes.
    @Test("the list is stable")
    func stable() {
        let source = "const zebra = 1\nconst apple = 2\nconst mango = 3"

        #expect(names(in: source) == ["apple", "mango", "zebra"])
    }

    /// Later wins, so a name re-declared points at where it is now.
    @Test("a redeclared name reports its latest line")
    func redeclared() throws {
        let found = try #require(
            ScriptDeclarations.all(in: "let x = 1\nlet x = 2").first { $0.name == "x" },
        )

        #expect(found.line == 2)
    }

    // MARK: - What must NOT be found

    /// A commented-out declaration offered as real is worse than a missing one:
    /// it says something exists that does not.
    @Test("a commented declaration is not found")
    func commented() {
        #expect(names(in: "// const fake = 1").isEmpty)
        #expect(names(in: "const real = 1 // const fake = 2") == ["real"])
    }

    /// Word boundaries, so a longer word containing a keyword is not one.
    @Test("a word containing a keyword is not a declaration", arguments: [
        "constant = 1",
        "myLet = 1",
        "obj.const = 1",
        "variance = 1",
    ])
    func notADeclaration(source: String) {
        #expect(names(in: source).isEmpty, "\(source) was read as a declaration")
    }

    /// A name cannot start with a digit.
    @Test("a numeric name is refused")
    func numericName() {
        #expect(names(in: "const 1bad = 1").isEmpty)
    }

    /// Destructuring yields nothing rather than a guess.
    @Test("destructuring is skipped rather than guessed at")
    func destructuring() {
        #expect(names(in: "const { a, b } = thing").isEmpty)
    }

    // MARK: - The real thing

    /// The starter template, which is what somebody sees first.
    @Test("the starter template's own names are found")
    func starterTemplate() {
        let source = """
        const count = 24

        for (let i = 0; i < count; i++) {
          const angle = (i / count) * Math.PI * 2
          const born = (i / count) * duration * 0.5
        }
        """

        #expect(names(in: source) == ["angle", "born", "count", "i"])
    }
}
