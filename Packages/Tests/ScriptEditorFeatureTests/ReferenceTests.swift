import Testing

@testable import ScriptEditorFeature

/// The reference covers what a script can actually call.
///
/// Generated from `ScriptAPI`, so it cannot drift — but it can be
/// *incomplete*, which is the failure that matters: a reference missing a
/// section reads as "that does not exist" rather than as "we forgot".
@Suite("Scripting reference")
struct ReferenceTests {
    /// Every group a script can reach has entries.
    @Test("no group is empty", arguments: [
        ("globals", ScriptAPI.globals),
        ("sprite methods", ScriptAPI.spriteMethods),
        ("images", ScriptAPI.images),
        ("easings", ScriptAPI.easings),
        ("random", ScriptAPI.randomMethods),
        ("layers", ScriptAPI.layers),
        ("origins", ScriptAPI.origins),
        ("console", ScriptAPI.consoleMethods),
    ])
    func groupHasEntries(name: String, entries: [ScriptAPI.Entry]) {
        #expect(!entries.isEmpty, "\(name) is empty, so the reference will not mention it")
    }

    /// The counts that are fixed by the format, so a missing one is caught.
    @Test("the fixed-size groups are complete")
    func fixedSizes() {
        #expect(ScriptAPI.easings.count == 35, "the format has 35 curves")
        #expect(ScriptAPI.layers.count == 5, "osu! has 5 layers")
        #expect(ScriptAPI.origins.count == 9, "osu! has 9 origins")
        #expect(ScriptAPI.spriteMethods.count == 12, "9 command kinds plus at, flipH, flipV")
    }

    /// Everything has a one-line summary.
    ///
    /// An entry with no summary is a name in a list, and a name alone is what
    /// the reference exists to improve on.
    @Test("every entry says what it is")
    func everyEntryHasASummary() {
        let all = ScriptAPI.globals + ScriptAPI.spriteMethods + ScriptAPI.images
            + ScriptAPI.easings + ScriptAPI.randomMethods + ScriptAPI.consoleMethods

        for entry in all {
            #expect(!entry.summary.isEmpty, "\(entry.name) has no summary")
        }
    }

    /// The things somebody reaches for first carry a worked example.
    ///
    /// Not everything needs one — `Ease.quadOut` is a value, and an example of
    /// a value is the value. What needs one is anything callable, where the
    /// argument order is the question.
    @Test("everything callable has an example", arguments: [
        ScriptAPI.globals, ScriptAPI.spriteMethods,
    ])
    func callablesHaveExamples(group: [ScriptAPI.Entry]) {
        for entry in group where entry.kind == .function || entry.kind == .method {
            #expect(entry.example != nil, "\(entry.name) is callable with no example")
        }
    }

    /// A namespace is described, so the reference can head its section.
    @Test("every namespace global is described")
    func namespacesDescribed() {
        for entry in ScriptAPI.globals where entry.kind == .namespace {
            #expect(!entry.summary.isEmpty)
            #expect(!ScriptAPI.members(of: entry.name).isEmpty || entry.name == "Math",
                    "\(entry.name) is a namespace with no members the reference can list")
        }
    }
}
