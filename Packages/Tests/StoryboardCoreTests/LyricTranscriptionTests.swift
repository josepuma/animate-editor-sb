import Foundation
import Testing

@testable import StoryboardCore

/// The grouper, tested against words a real transcription produced.
///
/// The fixture is not invented: it is the 400 glyphs `SpeechAnalyzer` returned
/// for "Lia — Toki wo Kizamu Uta", timings and confidences included. A grouper
/// tested on hand-written input agrees with whatever the author imagined the
/// model does, which is the one thing worth checking.
@Suite("Lyric line grouping")
struct LyricTranscriptionTests {
    // ─── Fixture ─────────────────────────────────────────────────────────────

    private struct FixtureWord: Decodable {
        var text: String
        var start: Double
        var end: Double
        var confidence: Double
    }

    private static func japaneseWords() throws -> [LyricTranscription.Word] {
        let url = try #require(
            Bundle.module.url(
                forResource: "lyric-words-ja", withExtension: "json", subdirectory: "Fixtures",
            ) ?? Bundle.module.url(forResource: "lyric-words-ja", withExtension: "json"),
            "the measured Japanese fixture has to be in the bundle",
        )
        let decoded = try JSONDecoder().decode([FixtureWord].self, from: Data(contentsOf: url))
        return decoded.map {
            LyricTranscription.Word(
                text: $0.text, start: $0.start, end: $0.end, confidence: $0.confidence,
            )
        }
    }

    private static func word(
        _ text: String, _ start: Double, _ end: Double, confidence: Double? = 0.9,
    ) -> LyricTranscription.Word {
        LyricTranscription.Word(text: text, start: start, end: end, confidence: confidence)
    }

    // ─── Splitting ───────────────────────────────────────────────────────────

    @Test("a gap starts a new line and contiguous words do not")
    func gapSplits() {
        let words = [
            Self.word("落", 0, 300),
            Self.word("ち", 300, 540),
            // 900ms of silence: a different sung phrase.
            Self.word("逆", 1440, 1740),
            Self.word("さ", 1740, 2160),
        ]

        let lines = LyricTranscription.lines(from: words)

        #expect(lines.count == 2)
        #expect(lines[0].text == "落ち")
        #expect(lines[1].text == "逆さ")
        // The line spans its own words, not the silence between them.
        #expect(lines[0].start == 0)
        #expect(lines[0].end == 540)
        #expect(lines[1].start == 1440)
    }

    /// Verses come out as verses, and it takes both rules to get there.
    ///
    /// Written after two wrong measurements, and worth recording because each
    /// one was wrong in a way that looked right:
    ///
    /// 1. A gap histogram of the **raw** transcription showed a wide empty band
    ///    where any threshold would do. It was an artefact: the model's
    ///    invented `。` sat inside those silences, so one real 420ms gap counted
    ///    as two gaps of nothing. Filtering punctuation — which the pipeline
    ///    does — uncovered nine gaps between 240 and 660ms, all verse
    ///    boundaries. *An instrument that counts what the code discards is
    ///    measuring a different pipeline.*
    /// 2. With the band exposed, 350ms merged three verses into thirty-four
    ///    characters and 200 did not — so the gap looked like the whole story.
    ///    It is not: the character limit splits that merge anyway, and with
    ///    both rules the two thresholds agree to within one line out of
    ///    seventy-three.
    ///
    /// So this pins the **outcome** rather than the knob: whichever rule earns
    /// it, these two verses arrive whole and separate.
    @Test("verses arrive whole and separate", arguments: [200.0, 350.0])
    func versesSurviveGrouping(threshold: Double) throws {
        let lines = LyricTranscription.lines(
            from: try Self.japaneseWords(), gapThreshold: threshold,
        )

        // Sung 5.3 seconds apart, verified by ear against the song.
        #expect(lines.contains { $0.text == "落ちてゆく砂時計ばかり見てるよ" })
        #expect(lines.contains { $0.text == "逆さまにすればほらまだ始まるよ" })
    }

    @Test("a real song groups into the lines it was sung as")
    func realSongGroups() throws {
        let lines = LyricTranscription.lines(from: try Self.japaneseWords())

        // Verified by ear against the song: the first sung line of Toki wo
        // Kizamu Uta, at the time the transcription measured.
        let opening = try #require(lines.first { $0.text.contains("砂時計") })
        #expect(opening.text == "落ちてゆく砂時計ばかり見てるよ")
        #expect(opening.start == 16680)

        #expect(lines.count > 15)
    }









    // ─── Punctuation ─────────────────────────────────────────────────────────

    /// The model emits `。` as a word with its own time range and a confidence
    /// around 0.7. Left in, every sentence end becomes a sprite: a full stop
    /// floating in the storyboard that nobody asked for and nothing explains.
    @Test("punctuation the model invents does not become a glyph")
    func punctuationIsDropped() {
        let words = [
            Self.word("見", 0, 300),
            Self.word("て", 300, 540),
            Self.word("る", 540, 780),
            Self.word("。", 780, 1020, confidence: 0.74),
        ]

        let lines = LyricTranscription.lines(from: words)

        #expect(lines.count == 1)
        #expect(lines[0].text == "見てる")
        // And the line ends where the singing ends, not where the invented
        // punctuation does.
        #expect(lines[0].end == 780)
    }

    @Test("dropping punctuation cannot leave an empty line")
    func punctuationOnlyLineVanishes() {
        let words = [
            Self.word("あ", 0, 300),
            // A stray full stop alone in its own gap.
            Self.word("。", 2000, 2100, confidence: 0.62),
            Self.word("い", 4000, 4300),
        ]

        let lines = LyricTranscription.lines(from: words)

        #expect(lines.count == 2)
        #expect(lines.allSatisfy { !$0.text.isEmpty })
    }

    // ─── Joining ─────────────────────────────────────────────────────────────

    /// The spacing arrives in the data, so the joiner does not invent any.
    ///
    /// Measured against a real `AttributedString` run: the engine returns
    /// `"Me,"` then `" girl,"` — the space **leading** each word after the
    /// first. Japanese returns bare glyphs with no space at all. So each script
    /// already spaces itself correctly and concatenation is the whole answer.
    ///
    /// The first version guessed instead, joining with a space unless it
    /// detected CJK glyphs. That produced `"Me,  girl,  you"` — every English
    /// gap doubled — and was found end to end, because a doubled space is
    /// invisible in most output and the Japanese case it was built for looked
    /// perfect.
    @Test("Japanese glyphs concatenate")
    func japaneseJoinsTight() {
        let lines = LyricTranscription.lines(from: [
            Self.word("落", 0, 300),
            Self.word("ち", 300, 540),
            Self.word("て", 540, 780),
        ])

        #expect(lines[0].text == "落ちて")
    }

    @Test("English keeps the spacing the engine gave it, and no more")
    func englishJoinsSpaced() {
        // Exactly the shape the engine returns: leading spaces, not trailing.
        let lines = LyricTranscription.lines(from: [
            Self.word("I'm", 0, 300),
            Self.word(" still", 300, 540),
            Self.word(" in", 540, 780),
            Self.word(" love", 780, 1080),
        ])

        #expect(lines[0].text == "I'm still in love")
    }

    @Test("a line never begins or ends with the engine's spacing")
    func linesAreTrimmed() {
        // The first word of a *line* still carries its leading space when the
        // line began mid-sentence, which is most of them.
        let lines = LyricTranscription.lines(from: [
            Self.word(" you", 0, 300),
            Self.word(" cheated", 300, 900),
        ])

        #expect(lines[0].text == "you cheated")
    }

    // ─── Confidence ──────────────────────────────────────────────────────────

    /// Measured, confidence discriminates: `love` came back at 0.98 and was
    /// right, `ever` at 0.12 and was wrong. A line is only as trustworthy as
    /// its worst word, so the minimum is what the UI has to show — an average
    /// would bury one bad word among five good ones, which is exactly the word
    /// somebody needs to find.
    @Test("a line reports its least confident word")
    func lineTakesTheWorstConfidence() {
        let lines = LyricTranscription.lines(from: [
            Self.word("I", 0, 200, confidence: 0.92),
            Self.word("was", 200, 400, confidence: 0.72),
            Self.word("lying", 400, 900, confidence: 0.14),
        ])

        #expect(lines[0].confidence == 0.14)
    }

    @Test("a line of words with no confidence has none")
    func missingConfidenceStaysMissing() {
        let lines = LyricTranscription.lines(from: [
            Self.word("a", 0, 200, confidence: nil),
            Self.word("b", 200, 400, confidence: nil),
        ])

        #expect(lines[0].confidence == nil)
    }

    // ─── Degenerate input ────────────────────────────────────────────────────

    @Test("no words is no lines")
    func emptyInput() {
        #expect(LyricTranscription.lines(from: []).isEmpty)
    }

    @Test("words arriving out of order are still grouped by time")
    func unsortedInput() {
        // Nothing observed produces this, and a grouper that trusts the order
        // it is handed would silently split a line in two if anything ever did.
        let lines = LyricTranscription.lines(from: [
            Self.word("て", 540, 780),
            Self.word("落", 0, 300),
            Self.word("ち", 300, 540),
        ])

        #expect(lines.count == 1)
        #expect(lines[0].text == "落ちて")
    }
}

/// Splitting a line that holds two sentences.
///
/// Reported from a real song: *"eran 2 oraciones y aquí se andan juntando como
/// una"*. And there is no silence to cut at — measured across 249 words, **every
/// gap inside a line is exactly 0ms**, and the fifteen punctuation marks the
/// model emits all land where a gap already cuts. Neither signal helps.
///
/// **Duration does.** A line of one sentence runs about five seconds; the merged
/// ones ran ten to thirteen. Nobody sings thirteen seconds without breathing, so
/// the length of a line is itself the evidence that there is more than one
/// sentence in it — and unlike a glyph count, it is a physical limit rather than
/// an arbitrary number, and it means the same thing in every language.
@Suite("Lyric sentence splitting")
struct LyricDurationSplitTests {
    private struct FixtureWord: Decodable {
        var text: String
        var start: Double
        var end: Double
        var confidence: Double
    }

    private static func japaneseWords() throws -> [LyricTranscription.Word] {
        let url = try #require(
            Bundle.module.url(
                forResource: "lyric-words-ja", withExtension: "json", subdirectory: "Fixtures",
            ) ?? Bundle.module.url(forResource: "lyric-words-ja", withExtension: "json"),
        )
        return try JSONDecoder().decode([FixtureWord].self, from: Data(contentsOf: url)).map {
            LyricTranscription.Word(
                text: $0.text, start: $0.start, end: $0.end, confidence: $0.confidence,
            )
        }
    }

    /// The line from the report arrives whole, and says it is too long.
    ///
    /// It cannot be cut: measured, this line has **no internal gap at all** —
    /// like all eight of this song's over-long lines. Splitting it anyway means
    /// guessing at the sentence boundary, and a wrong guess breaks a word in
    /// half (「ここで優しい暖か」 / 「さを思い返してる」 is what that looked
    /// like). So it is flagged rather than cut.
    @Test("a long line with no breath is flagged, not cut blindly")
    func overlongLineIsFlaggedNotCut() throws {
        let lines = LyricTranscription.lines(from: try Self.japaneseWords())

        let merged = try #require(lines.first { $0.text.contains("暖かな日だまり") })
        #expect(merged.isOverlong)
        #expect(merged.duration > LyricTranscription.maximumLineDuration)
    }

    @Test("a line short enough is not flagged")
    func normalLineIsNotFlagged() throws {
        let lines = LyricTranscription.lines(from: try Self.japaneseWords())

        let sane = try #require(lines.first { $0.text == "落ちてゆく砂時計ばかり見てるよ" })
        #expect(!sane.isOverlong)
    }

    /// The flag is what the panel needs, so it has to actually find the lines
    /// worth flagging — a flag nobody sets is a column of blanks.
    @Test("a real song has lines to flag, and most lines are fine")
    func flagsAreUseful() throws {
        let lines = LyricTranscription.lines(from: try Self.japaneseWords())
        let flagged = lines.count(where: \.isOverlong)

        #expect(flagged > 0, "nothing flagged: the panel would show no work to do")
        #expect(flagged < lines.count / 2, "\(flagged) of \(lines.count) flagged")
    }

    /// The split falls at the widest gap inside the line, which is the breath
    /// between sentences even when it is under the grouping threshold.
    ///
    /// The phrases are deliberately **uneven** — nine glyphs then three. A
    /// symmetric case cannot tell this rule from "cut at the halfway glyph":
    /// the first version of this test used six and six, and passed with the
    /// gap search disabled entirely.
    @Test("the break lands at the breath, not at the midpoint")
    func breakFollowsTheWidestGap() {
        var words: [LyricTranscription.Word] = []
        // Nine glyphs at 200ms each: 1.8 seconds.
        for index in 0..<9 {
            words.append(.init(
                text: "あ", start: Double(index) * 200, end: Double(index) * 200 + 180,
            ))
        }
        // A 150ms breath — under the 200ms grouping threshold, so the line
        // stays whole — then three more glyphs. Total 2.7s.
        for index in 0..<3 {
            let base = 1930.0 + Double(index) * 200
            words.append(.init(text: "い", start: base, end: base + 180))
        }

        // Over the limit once, so it splits exactly once, and each half is
        // then short enough to survive.
        let lines = LyricTranscription.lines(from: words, maximumDuration: 2000)

        #expect(lines.count == 2)
        // Nine and three. Cutting at the midpoint would give six and six.
        #expect(lines[0].text == String(repeating: "あ", count: 9))
        #expect(lines[1].text == String(repeating: "い", count: 3))
    }

    @Test("a line already short enough is untouched")
    func shortLinesSurvive() {
        let words = (0..<4).map { index in
            LyricTranscription.Word(
                text: "落", start: Double(index) * 300, end: Double(index) * 300 + 280,
            )
        }

        let lines = LyricTranscription.lines(from: words, maximumDuration: 7000)

        #expect(lines.count == 1)
        #expect(lines[0].text == "落落落落")
    }

    /// The knob changes what gets **flagged**, which is not the same as what
    /// gets cut: a line with no breath is never cut however low the limit
    /// goes, so counting lines would have shown the knob doing nothing.
    @Test("a tighter limit flags more lines")
    func limitIsAdjustable() throws {
        let words = try Self.japaneseWords()

        let loose = LyricTranscription.lines(from: words, maximumDuration: 12_000)
        let tight = LyricTranscription.lines(from: words, maximumDuration: 4_000)

        #expect(tight.count(where: \.isOverlong) > loose.count(where: \.isOverlong))
    }
}
