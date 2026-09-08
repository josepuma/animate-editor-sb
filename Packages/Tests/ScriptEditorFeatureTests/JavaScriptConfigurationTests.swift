import LanguageSupport
import Testing

@testable import ScriptEditorFeature

/// The JavaScript colouring, and the one thing about it that can go silently
/// wrong.
@Suite("JavaScript configuration")
struct JavaScriptConfigurationTests {
    private let language = LanguageConfiguration.javaScript()

    @Test("it declares itself as JavaScript")
    func named() {
        #expect(language.name == "JavaScript")
    }

    /// The host's globals are coloured as reserved, so they have to BE the
    /// host's globals.
    ///
    /// A name coloured here that a script cannot actually call is worse than no
    /// colour at all: it says the call is fine right up until it throws. The
    /// engine's own list is the source of truth, and this is the only thing
    /// holding the two in step — they are in different targets, so nothing else
    /// would notice one moving.
    ///
    /// Deliberately not asserting the whole list is equal: the engine also
    /// hands over the language's own globals and the loop guard, which are not
    /// things to colour as API. The claim is narrower and the one that matters:
    /// every storyboard name this colours must exist at runtime.
    @Test("every storyboard global it colours is one a script can call", arguments: [
        "sprite", "rng", "duration", "param", "params", "Image", "Ease",
        "Layer", "Origin", "console",
    ])
    func colouredGlobalsExist(name: String) {
        #expect(language.reservedIdentifiers.contains(name))
    }

    /// The three string forms JavaScript has, including the one Swift does not.
    @Test("all three string delimiters are recognised", arguments: [
        "\"double\"", "'single'", "`template`",
    ])
    func stringsAreRecognised(source: String) throws {
        let regex = try #require(language.stringRegex)

        #expect(source.wholeMatch(of: regex) != nil, "\(source) was not read as a string")
    }

    /// The number forms a script actually writes.
    @Test("number literals are recognised", arguments: [
        "0", "42", "3.14", ".5", "1e3", "1.5e-3", "0xFF", "0b1010", "0o777", "1_000",
    ])
    func numbersAreRecognised(source: String) throws {
        let regex = try #require(language.numberRegex)

        #expect(source.wholeMatch(of: regex) != nil, "\(source) was not read as a number")
    }

    /// `$` and `_` are identifier characters in JavaScript, unlike Swift.
    @Test("identifiers allow the characters JavaScript allows", arguments: [
        "count", "_private", "$element", "camelCase", "a1",
    ])
    func identifiersAreRecognised(source: String) throws {
        let regex = try #require(language.identifierRegex)

        #expect(source.wholeMatch(of: regex) != nil, "\(source) was not read as an identifier")
    }

    /// A digit cannot start one, or `1e3` would colour as a name.
    @Test("an identifier cannot start with a digit")
    func identifiersRejectLeadingDigits() throws {
        let regex = try #require(language.identifierRegex)

        #expect("1abc".wholeMatch(of: regex) == nil)
    }
}
