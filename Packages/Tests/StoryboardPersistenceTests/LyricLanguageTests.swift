import Foundation
import Testing

@testable import StoryboardPersistence

/// Turning the engine's locale identifiers into a picker somebody can read.
///
/// `zh_TW` says nothing to whoever is mapping a song. "Chinese", and then
/// "Taiwan (Traditional)" when it matters, does — and the 45 identifiers Apple
/// reports collapse to 25 languages, so the first menu gets much shorter too.
///
/// Everything here reads `Locale`, so there is no table of names to keep in
/// step with the OS.
@Suite("Lyric languages")
struct LyricLanguageTests {
    /// The real list, as measured: 45 identifiers, 25 distinct languages.
    private static let identifiers = [
        "bn_IN", "de_AT", "de_CH", "de_DE", "en_AU", "en_CA", "en_GB", "en_IE",
        "en_IN", "en_NZ", "en_SG", "en_US", "en_ZA", "es_CL", "es_ES", "es_MX",
        "es_US", "fr_BE", "fr_CA", "fr_CH", "fr_FR", "gu_IN", "hi_IN", "it_CH",
        "it_IT", "ja_JP", "kn_IN", "ko_KR", "ks_IN", "mai_IN", "ml_IN", "mr_IN",
        "mul_IN", "ne_IN", "or_IN", "pa_IN", "pt_BR", "pt_PT", "ta_IN", "te_IN",
        "ur_IN", "yue_CN", "zh_CN", "zh_HK", "zh_TW",
    ]

    // ─── Languages ───────────────────────────────────────────────────────────

    @Test("forty-five identifiers become twenty-five languages")
    func groupsIntoLanguages() {
        let languages = LyricLanguage.languages(from: Self.identifiers)

        #expect(languages.count == 25)
    }

    /// Asserted against what the system itself says, not against the English
    /// word: names come from `Locale.current`, so on a Spanish Mac Chinese is
    /// "chino" — which is right, and is why the first version of this test
    /// failed on a correct implementation.
    @Test("a language is named, not coded", arguments: ["zh", "ja", "en"])
    func languagesAreNamed(code: String) throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)
        let language = try #require(languages.first { $0.code == code })

        #expect(language.name == Locale.current.localizedString(forLanguageCode: code))
        // And not the bare code, which is what a mapper cannot read.
        #expect(language.name != code)
    }

    /// Alphabetical by the name shown, not by the code behind it.
    ///
    /// The first version asserted `names == names.sorted()` and **passed with
    /// the sort keyed on `code`**, because in this sample the two orders happen
    /// to agree. This one names a pair where they cannot: `de` sorts before
    /// `ja` by code, and in English "German" comes after "Japanese" — in
    /// Spanish "alemán" comes before "japonés", so the assertion is written
    /// against whichever the system says rather than against a fixed order.
    @Test("languages are sorted by the name on screen")
    func languagesAreSortedByName() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)
        let names = languages.map(\.name)

        #expect(names == names.sorted())

        // And a pair whose two orders disagree, so the sort key is pinned.
        let german = try #require(names.firstIndex(of: Locale.current.localizedString(forLanguageCode: "de") ?? "de"))
        let japanese = try #require(names.firstIndex(of: Locale.current.localizedString(forLanguageCode: "ja") ?? "ja"))
        let byName = (names[german] < names[japanese])
        #expect((german < japanese) == byName)
    }

    @Test("a language with one region carries it")
    func singleRegionLanguage() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)

        let japanese = try #require(languages.first { $0.code == "ja" })
        #expect(japanese.variants.count == 1)
        #expect(japanese.variants[0].identifier == "ja_JP")
        // Nothing to choose, so the panel shows no region field for it.
        #expect(!japanese.hasChoice)
    }

    @Test("a language with several regions offers them")
    func multiRegionLanguage() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)

        let english = try #require(languages.first { $0.code == "en" })
        #expect(english.variants.count == 9)
        #expect(english.hasChoice)
    }

    // ─── Regions ─────────────────────────────────────────────────────────────

    @Test("a region is named the way the system names it")
    func regionsAreNamed() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)
        let english = try #require(languages.first { $0.code == "en" })

        let names = english.variants.map(\.name)
        for code in ["US", "GB"] {
            let expected = try #require(Locale.current.localizedString(forRegionCode: code))
            #expect(names.contains(expected))
        }
        // No identifier leaked through as its raw form.
        #expect(!names.contains { $0.contains("_") })
    }

    /// The one case where the region alone is not the useful distinction:
    /// `zh_TW` transcribes in traditional characters and `zh_CN` in simplified,
    /// and those are different text on screen. The script goes in the label.
    @Test("Chinese says traditional or simplified, because that is what differs")
    func chineseNamesItsScript() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)
        let chinese = try #require(languages.first { $0.code == "zh" })

        // Compared against the *shortened* names — the family word is dropped
        // because the language menu above already carries it, so the label
        // says "(simplificado)" rather than "(han simplificado)".
        let names = chinese.variants.map(\.name)
        let family = try #require(Locale.current.localizedString(forScriptCode: "Hani"))
        func short(_ code: String) -> String {
            (Locale.current.localizedString(forScriptCode: code) ?? code)
                .replacingOccurrences(of: family, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
        }
        let traditional = short("Hant")
        let simplified = short("Hans")
        #expect(names.contains { $0.contains(traditional) })
        #expect(names.contains { $0.contains(simplified) })

        // And still says where, since Taiwan and Hong Kong are both traditional.
        let taiwan = try #require(Locale.current.localizedString(forRegionCode: "TW"))
        #expect(names.contains { $0.contains(taiwan) })
    }

    @Test("a script is only named where it distinguishes something")
    func scriptIsOmittedWhenItSaysNothing() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers)
        let english = try #require(languages.first { $0.code == "en" })

        // Every English locale is Latin, so saying so on all nine is noise.
        #expect(!english.variants.contains { $0.name.contains("Latn") })
        #expect(!english.variants.contains { $0.name.contains("Latin") })
    }

    /// The script's family name is dropped, because the language menu above
    /// already carries it.
    ///
    /// The system says "han simplificado", so the full label was "China
    /// continental (han simplificado)" — thirty-six characters, and the panel
    /// truncated it on screen.
    @Test("a script label does not repeat the language")
    func scriptLabelIsShort() throws {
        let languages = LyricLanguage.languages(from: ["zh_CN", "zh_TW"])
        let chinese = try #require(languages.first)

        let family = try #require(Locale.current.localizedString(forScriptCode: "Hani"))
        for variant in chinese.variants {
            #expect(
                !variant.name.localizedCaseInsensitiveContains(family),
                "\(variant.name) repeats \(family)",
            )
        }
        // And still distinguishes the two, which is the whole reason it is
        // there.
        #expect(Set(chinese.variants.map(\.name)).count == 2)
    }

    // ─── Picking ─────────────────────────────────────────────────────────────

    /// An installed model starts transcribing in seconds; anything else
    /// downloads first. So when a language has several regions and one is
    /// already here, that is the one to default to.
    @Test("an installed region is preferred")
    func prefersAnInstalledRegion() throws {
        let languages = LyricLanguage.languages(
            from: Self.identifiers, installed: ["en_GB", "zh_CN"],
        )

        let english = try #require(languages.first { $0.code == "en" })
        #expect(english.preferred.identifier == "en_GB")

        let chinese = try #require(languages.first { $0.code == "zh" })
        #expect(chinese.preferred.identifier == "zh_CN")
    }

    @Test("with nothing installed the first region is used")
    func fallsBackToTheFirstRegion() throws {
        let languages = LyricLanguage.languages(from: Self.identifiers, installed: [])

        let english = try #require(languages.first { $0.code == "en" })
        #expect(english.variants.contains { $0.identifier == english.preferred.identifier })
    }

    @Test("an installed variant says so, so the wait is predictable")
    func installedIsMarked() throws {
        let languages = LyricLanguage.languages(
            from: Self.identifiers, installed: ["ja_JP"],
        )

        let japanese = try #require(languages.first { $0.code == "ja" })
        #expect(japanese.variants[0].isInstalled)

        let korean = try #require(languages.first { $0.code == "ko" })
        #expect(!korean.variants[0].isInstalled)
    }

    /// The engine spells them with an underscore and `Locale` with a hyphen,
    /// and a comparison that misses turns "already installed" into a download
    /// on every run.
    @Test("installed matching survives the spelling difference")
    func matchingIgnoresSeparator() throws {
        let languages = LyricLanguage.languages(
            from: ["ja_JP"], installed: ["ja-JP"],
        )

        let japanese = try #require(languages.first)
        #expect(japanese.variants[0].isInstalled)
    }

    // ─── Degenerate input ────────────────────────────────────────────────────

    @Test("no identifiers means no languages")
    func emptyInput() {
        #expect(LyricLanguage.languages(from: []).isEmpty)
    }

    @Test("an identifier the system cannot name is still offered")
    func unnameableIdentifierSurvives() {
        // `mul` is "Multiple languages" and real in Apple's list; whatever the
        // system calls it, dropping it would hide a model that works.
        let languages = LyricLanguage.languages(from: ["mul_IN"])

        #expect(languages.count == 1)
        #expect(!languages[0].name.isEmpty)
    }
}
