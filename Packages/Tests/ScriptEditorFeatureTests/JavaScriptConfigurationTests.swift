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

    /// Members colour too, not just their namespace.
    ///
    /// Reported as "the enums have no syntax": `Ease` was in the list and
    /// `quadOut` was not, so `Ease.quadOut` drew as a coloured receiver
    /// followed by a plain word. Not a limit of regex highlighting — a limit of
    /// an incomplete table.
    @Test("a namespace member is coloured", arguments: [
        "quadOut", "soft", "fade", "unit", "Centre", "Overlay",
    ])
    func membersAreColoured(name: String) {
        #expect(language.reservedIdentifiers.contains(name))
    }

    /// And a name that does not exist is not.
    ///
    /// Colouring everything would be the same as colouring nothing: the point
    /// of the highlight is that it distinguishes a name the host provides from
    /// one somebody typed.
    @Test("an unknown name is not coloured", arguments: [
        "notAThing", "myVariable", "count",
    ])
    func unknownIsNotColoured(name: String) {
        #expect(language.reservedIdentifiers.contains(name) == false)
    }

    /// Every name the completion list offers is a name the highlighter knows.
    ///
    /// The two lists are the same data now, and this says so — the version
    /// where they were written separately had one of them spelled backwards
    /// for all thirty-five easings.
    @Test("everything completable is highlightable")
    func completionAndHighlightingAgree() {
        let highlighted = Set(language.reservedIdentifiers)
        let completable = ScriptAPI.easings + ScriptAPI.images + ScriptAPI.layers
            + ScriptAPI.origins + ScriptAPI.spriteMethods + ScriptAPI.randomMethods

        for entry in completable {
            #expect(highlighted.contains(entry.name), "\(entry.name) completes but does not colour")
        }
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
