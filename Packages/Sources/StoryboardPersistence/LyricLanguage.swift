import Foundation

/// A language somebody can pick, built out of the identifiers the speech
/// engine reports.
///
/// `zh_TW` says nothing to whoever is mapping a song, and Apple reports
/// **forty-five** of those — nine of them English. Grouped by language the
/// first menu is twenty-five entries with names on them, and the region only
/// appears where there is something to choose.
///
/// Everything here is read from `Locale`, so there is no table of names to
/// keep in step with the OS.
public struct LyricLanguage: Identifiable, Sendable, Equatable {
    /// One region's model for this language.
    public struct Variant: Identifiable, Sendable, Equatable {
        /// The identifier to hand back to the engine, in its own spelling.
        public let identifier: String
        /// What to show: the region, plus the script where that is the real
        /// distinction.
        public let name: String
        /// Whether the model is already on the machine.
        public let isInstalled: Bool

        public var id: String { identifier }
    }

    /// The language subtag — `zh`, `en`, `ja`.
    public let code: String
    /// The language's own name, localised.
    public let name: String
    public let variants: [Variant]

    public var id: String { code }

    /// Whether a region field is worth showing at all.
    public var hasChoice: Bool { variants.count > 1 }

    /// Which region to start on.
    ///
    /// An installed model transcribes in seconds and anything else downloads
    /// first, so an installed region wins — that is the difference the author
    /// actually feels.
    public var preferred: Variant {
        variants.first(where: \.isInstalled) ?? variants[0]
    }

    // ─── Building ────────────────────────────────────────────────────────────

    /// Groups the engine's identifiers into languages.
    ///
    /// - Parameters:
    ///   - identifiers: what the engine supports, in its own spelling.
    ///   - installed: which of them are already downloaded.
    public static func languages(
        from identifiers: [String],
        installed: [String] = [],
    ) -> [LyricLanguage] {
        // Canonicalised, because the engine spells them with an underscore and
        // `Locale` with a hyphen — a comparison that misses turns "already
        // installed" into a download on every run.
        let installedSet = Set(installed.map(canonical))

        let grouped = Dictionary(grouping: identifiers) { identifier in
            Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        }

        return grouped
            .map { code, ids in
                LyricLanguage(
                    code: code,
                    name: languageName(code),
                    variants: variants(for: ids, installed: installedSet),
                )
            }
            // By the name on screen, not the code behind it: sorted by code,
            // Bangla lands before German before English for reasons nobody
            // reading the list can see.
            .sorted { $0.name < $1.name }
    }

    private static func variants(
        for identifiers: [String],
        installed: Set<String>,
    ) -> [Variant] {
        // Whether naming the script tells anyone anything. Every English
        // locale is Latin, so saying so nine times is noise; Chinese splits
        // into traditional and simplified, which is different text on screen.
        let scripts = Set(identifiers.compactMap {
            Locale(identifier: $0).language.script?.identifier
        })
        let scriptDistinguishes = scripts.count > 1

        return identifiers
            .map { identifier in
                Variant(
                    identifier: identifier,
                    name: variantName(identifier, includingScript: scriptDistinguishes),
                    isInstalled: installed.contains(canonical(identifier)),
                )
            }
            .sorted { $0.name < $1.name }
    }

    // ─── Naming ──────────────────────────────────────────────────────────────

    /// The language's name, or the code itself when the system has none.
    ///
    /// Falling back to the code rather than dropping the entry: whatever the
    /// system calls `mul`, hiding it would hide a model that works.
    private static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private static func variantName(_ identifier: String, includingScript: Bool) -> String {
        let locale = Locale(identifier: identifier)
        let region = locale.region
            .flatMap { Locale.current.localizedString(forRegionCode: $0.identifier) }
            ?? identifier

        guard includingScript, let script = locale.language.script else { return region }

        // The script's *short* form. `localizedString(forScriptCode:)` returns
        // "han simplificado", which with the region makes "China continental
        // (han simplificado)" — thirty-six characters, and the panel truncated
        // it. The language menu above already says Chinese, so repeating "han"
        // in every region label spends the width on the one word that adds
        // nothing.
        return "\(region) (\(shortScriptName(script.identifier)))"
    }

    /// What distinguishes one script from another, without repeating the
    /// language.
    ///
    /// Traditional and simplified are the distinction that matters — they are
    /// different text on screen — and they are the only pair the engine's list
    /// actually contains more than one of. Anything else falls back to the
    /// system's own name, which is right whatever it turns out to be.
    private static func shortScriptName(_ code: String) -> String {
        let full = Locale.current.localizedString(forScriptCode: code) ?? code

        // Drop the script family's own word, which the language menu above
        // already carries: the system says "han simplificado" and "simplified
        // Han", and either way "China continental (han simplificado)" is
        // thirty-six characters in a 240-point panel. Taking the family name
        // out leaves the half that distinguishes anything.
        //
        // Localised names rather than a hard-coded pair, so this reads
        // correctly in whatever language the system is set to.
        let family = Locale.current.localizedString(forScriptCode: "Hani") ?? "Han"
        let trimmed = full
            .replacingOccurrences(of: family, with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? full : trimmed
    }

    /// One spelling, so `ja_JP` and `ja-JP` compare equal.
    private static func canonical(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
