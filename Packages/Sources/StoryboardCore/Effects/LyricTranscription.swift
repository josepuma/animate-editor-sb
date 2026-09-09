import Foundation

/// Words heard in a song, with the moment each one was sung.
///
/// The half of a lyric storyboard nobody can do by hand. The words themselves
/// are a search away; marking four hundred of them to twenty milliseconds is
/// not, and it is the only part a machine is better at.
///
/// Core cannot listen to audio, so the words arrive from outside — from
/// `LyricTranscriber` in the platform layer, reached by the app. What lives
/// here is everything that follows, and it is pure: the words, and how they
/// become singable lines.
///
/// > There is deliberately **no seam** here, unlike ``AudioSpectrum/analyse``
/// and ``TextMetrics/measure``. Those exist because an *effect* asks for them
/// from inside `evaluate()`, where Core has no way out. Nothing in Core asks
/// for a transcription: the UI does, once, when somebody presses a button — so
/// it travels the route an export already takes, through a handler on the
/// shell that the app fills in. A seam nothing calls is dead code shaped like
/// architecture.
public enum LyricTranscription {
    // ─── What a transcription returns ────────────────────────────────────────

    /// One word, or in a script transcribed glyph by glyph, one glyph.
    public struct Word: Sendable, Equatable {
        public var text: String
        /// Milliseconds into the song, not into any clip.
        public var start: Double
        public var end: Double
        /// How sure the engine is, where it says.
        ///
        /// Measured, this discriminates rather than decorating: `love` came
        /// back at 0.98 and was right, `ever` at 0.12 and was wrong. It is what
        /// turns "check ninety-two words" into "check twenty-five".
        ///
        /// Optional because an engine that does not report one is a real
        /// possibility, and a default would be a number pretending to be a
        /// measurement.
        public var confidence: Double?

        public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
            self.text = text
            self.start = start
            self.end = end
            self.confidence = confidence
        }
    }

    /// A phrase, as it was sung — the unit a text clip holds.
    public struct Line: Sendable, Equatable, Identifiable {
        public var id: Double { start }
        public var text: String
        public var start: Double
        public var end: Double
        /// The confidence of this line's *least* certain word.
        ///
        /// The minimum, not the average: an average buries one bad word among
        /// five good ones, and that word is exactly the one somebody is looking
        /// for.
        public var confidence: Double?
        /// The words behind the text, kept so a later pass can align against
        /// them without transcribing the song again.
        public var words: [Word]

        /// Whether this line ran long enough to hold more than one sentence.
        ///
        /// Set when the line is over ``maximumLineDuration`` and had no breath
        /// to cut at, so nothing could be done about it automatically. The
        /// panel shows these so they can be split by hand — the alternative
        /// was a blind cut, which lands mid-word as often as between phrases.
        public var isOverlong = false

        public init(
            text: String,
            start: Double,
            end: Double,
            confidence: Double? = nil,
            words: [Word] = [],
            isOverlong: Bool = false,
        ) {
            self.text = text
            self.start = start
            self.end = end
            self.confidence = confidence
            self.words = words
            self.isOverlong = isOverlong
        }

        public var duration: Double { end - start }
    }

    // ─── What a picker needs ─────────────────────────────────────────────────

    /// A language offered in the panel, already named and grouped.
    ///
    /// Declared here rather than where it is built: the grouping needs
    /// `Locale` and the engine's list, which are the platform's, while the
    /// panel that draws it lives in a feature that imports neither. Core is
    /// the shared shape — the same arrangement every other seam here uses.
    public struct LanguageOption: Identifiable, Sendable, Equatable {
        /// One region's model.
        public struct Variant: Identifiable, Sendable, Equatable {
            /// What to hand back to the engine.
            public let identifier: String
            /// What to show: the region, and the script where that is the real
            /// distinction — traditional and simplified Chinese are different
            /// text on screen, not a dialect.
            public let label: String
            /// Whether it is downloaded. An installed model starts in seconds
            /// and anything else fetches first, which is the difference the
            /// author feels.
            public let isInstalled: Bool

            public var id: String { identifier }

            public init(identifier: String, label: String, isInstalled: Bool) {
                self.identifier = identifier
                self.label = label
                self.isInstalled = isInstalled
            }
        }

        /// The language's own name, localised — never its code.
        public let name: String
        public let variants: [Variant]

        public var id: String { name }

        /// Whether a region field is worth showing at all.
        public var hasChoice: Bool { variants.count > 1 }

        /// Which region to start on.
        public var preferred: String {
            (variants.first(where: \.isInstalled) ?? variants.first)?.identifier ?? ""
        }

        public init(name: String, variants: [Variant]) {
            self.name = name
            self.variants = variants
        }
    }

    // ─── Grouping ────────────────────────────────────────────────────────────

    /// How long a silence has to be to end a line.
    ///
    /// 200ms, measured rather than guessed — and the number moved once already.
    /// Counting gaps in the raw transcription suggested a wide empty band where
    /// any threshold would do, because the model's invented `。` sat *inside*
    /// those silences: a full stop between two verses turns one gap of 420ms
    /// into two gaps of nothing. Dropping the punctuation, which is right,
    /// uncovered nine real gaps between 240 and 660ms — exactly the band that
    /// looked empty.
    ///
    /// Those nine are verse boundaries. At 350ms three verses of Toki wo Kizamu
    /// Uta arrived as one clip of thirty-four characters; at 200 they are three
    /// clips of fifteen, which is what was sung.
    ///
    /// > The measurement has to filter what the code filters. An instrument
    /// that counts something the pipeline discards is measuring a different
    /// pipeline.
    public static let defaultGapThreshold: Double = 200

    /// How long a line may run before it is treated as more than one sentence.
    ///
    /// Silence is not the only thing that ends a line, because a singer does
    /// not always leave one — and when the engine runs two sentences together
    /// it leaves **nothing** to cut at: measured across 249 words, every gap
    /// inside a line is exactly 0ms, and the fifteen punctuation marks the
    /// model emits all fall where a gap already cuts.
    ///
    /// **Duration is the signal.** Measured on a real song, a line of one
    /// sentence runs about five seconds while the merged ones ran ten to
    /// thirteen — nobody sings thirteen seconds without breathing, so a line's
    /// own length is the evidence that there is more than one sentence in it.
    ///
    /// Seven seconds, and it is a physical limit rather than a chosen number:
    /// a phrase longer than that is not a phrase. Unlike a glyph count it also
    /// means the same thing in every language, where 25 characters is a long
    /// Japanese verse and five English words.
    public static let maximumLineDuration: Double = 7000

    /// Groups words into the phrases they were sung as.
    ///
    /// Pure, and the reason it lives in Core: no audio, no GPU, no window — it
    /// can be tested against the words a real transcription produced.
    public static func lines(
        from words: [Word],
        gapThreshold: Double = defaultGapThreshold,
        maximumDuration: Double = maximumLineDuration,
    ) -> [Line] {
        // Sorted before grouping. Nothing observed returns words out of order,
        // and a grouper that trusts the order it was handed would split a line
        // in two the day something does.
        let sung = words
            .filter { !isPunctuation($0.text) }
            .sorted { $0.start < $1.start }
        guard !sung.isEmpty else { return [] }

        var grouped: [[Word]] = [[sung[0]]]
        for word in sung.dropFirst() {
            let previous = grouped[grouped.count - 1].last!
            if word.start - previous.end >= gapThreshold {
                grouped.append([word])
            } else {
                grouped[grouped.count - 1].append(word)
            }
        }

        return grouped
            .flatMap { split($0, atMost: maximumDuration) }
            .compactMap { line(from: $0, longerThan: maximumDuration) }
    }

    /// Breaks a line that holds more than one sentence — **only where the
    /// singer breathed**.
    ///
    /// Measured on a real song, none of the eight over-long lines had any
    /// internal gap at all: every cut would have been blind, and a blind cut
    /// lands mid-word as often as between sentences (「ここで優しい暖か」 /
    /// 「さを思い返してる」). So duration says *there is more than one sentence
    /// here* and stops there — the line arrives whole, flagged by
    /// ``Line/isOverlong``, and where to break it is the author's call.
    ///
    /// At its widest internal gap, recursively — the weakest join in the
    /// phrase, which is the closest thing to a breath the transcription
    /// recorded. Splitting at the character count instead would cut mid-word.
    ///
    /// > **Ties break toward the middle**, and that is not a detail. A line
    /// sung without any pause has every gap at exactly zero, so "widest" has
    /// nothing to choose between: taking the first index found peels one glyph
    /// off the front and recurs on the rest, which turned a real 34-glyph line
    /// into thirty-four lines of one character. Found end to end, since a line
    /// of one glyph is still a line and nothing about the shape of the result
    /// says it is wrong.
    private static func split(_ words: [Word], atMost maximum: Double) -> [[Word]] {
        guard maximum > 0, words.count > 1 else { return [words] }
        let duration = words[words.count - 1].end - words[0].start
        guard duration > maximum else { return [words] }

        // No breath, no cut. Splitting anyway would be guessing at a sentence
        // boundary, and guessing wrong breaks a word in half.
        let hasBreath = (1..<words.count).contains { words[$0].start > words[$0 - 1].end }
        guard hasBreath else { return [words] }

        // Candidate splits exclude the ends: one there hands back an empty half
        // and recurs forever.
        let middle = Double(words.count) / 2
        var bestIndex = Int(middle.rounded())
        var bestGap = -Double.infinity
        var bestDistance = Double.infinity

        for index in 1..<words.count {
            let gap = words[index].start - words[index - 1].end
            let distance = abs(Double(index) - middle)
            // A wider gap always wins; an equal one goes to whichever is
            // closer to the centre.
            if gap > bestGap || (gap == bestGap && distance < bestDistance) {
                bestGap = gap
                bestDistance = distance
                bestIndex = index
            }
        }

        return split(Array(words[..<bestIndex]), atMost: maximum)
            + split(Array(words[bestIndex...]), atMost: maximum)
    }

    private static func line(from words: [Word], longerThan limit: Double) -> Line? {
        let text = join(words.map(\.text))
        guard !text.isEmpty else { return nil }

        // A line is only as trustworthy as its worst word. `compactMap` first,
        // so a line where nothing reported a confidence has none rather than
        // silently claiming zero.
        let confidences = words.compactMap(\.confidence)

        let start = words.first!.start
        let end = words.last!.end
        return Line(
            text: text,
            start: start,
            end: end,
            confidence: confidences.min(),
            words: words,
            isOverlong: end - start > limit,
        )
    }

    // ─── Text ────────────────────────────────────────────────────────────────

    /// Punctuation the engine inserted, which was never sung.
    ///
    /// The model emits `。` as a word of its own, with a time range and a
    /// confidence around 0.7 — indistinguishable from a real word by shape.
    /// Left in, every sentence end becomes a sprite: a full stop floating in
    /// the storyboard that nobody placed and nothing explains.
    private static func isPunctuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.allSatisfy { character in
            character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0)
                    || CharacterSet.symbols.contains($0)
            }
        }
    }

    /// Joins transcribed pieces back into a line.
    ///
    /// Concatenation, because **the spacing is already in the data**: measured
    /// against real results, the engine returns `"Me,"` then `" girl,"` — the
    /// space leading each word after the first — while Japanese returns bare
    /// glyphs with none. Each script spaces itself, and correctly.
    ///
    /// > The first version guessed instead, joining with a space unless it
    /// spotted CJK glyphs, and produced `"Me,  girl,  you"`: every English gap
    /// doubled. It survived the tests because they were written to the same
    /// guess, and it was caught end to end — a doubled space is invisible in
    /// most output, and the Japanese case the heuristic was built for looked
    /// perfect. *Thirty lines of script ranges, replaced by trusting the
    /// measurement.*
    ///
    /// Trimmed at the ends only: most lines begin mid-sentence, so their first
    /// word still carries the space that separated it from the previous line.
    private static func join(_ pieces: [String]) -> String {
        pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
