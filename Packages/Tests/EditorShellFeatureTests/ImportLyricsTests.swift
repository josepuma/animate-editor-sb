import Foundation
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Placing transcribed lines on the timeline.
///
/// The lines themselves are Core's and tested there; this is about what lands
/// in the document — one clip per line, at the time it was sung, in a single
/// edit somebody can undo with one keystroke.
@MainActor
@Suite("Importing lyrics")
struct ImportLyricsTests {
    private static func line(
        _ text: String, _ start: Double, _ end: Double, confidence: Double? = 0.9,
    ) -> LyricTranscription.Line {
        LyricTranscription.Line(
            text: text, start: start, end: end, confidence: confidence, words: [],
        )
    }

    /// Three lines of a real song, at the times the transcription measured.
    private static let sample: [LyricTranscription.Line] = [
        line("落ちてゆく砂時計ばかり見てるよ", 16_680, 21_780, confidence: 0.97),
        line("逆さまにすればほらまだ始まるよ", 22_020, 27_360, confidence: 0.66),
        line("刻んだだけ", 27_660, 30_000, confidence: 0.94),
    ]

    // ─── What lands ──────────────────────────────────────────────────────────

    @Test("one clip per line, at the time it was sung")
    func placesOneClipPerLine() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        let nodes = shell.effects.nodes
        #expect(nodes.count == 3)
        #expect(nodes.map(\.startTime) == [16_680, 22_020, 27_660])
        // The clip lasts as long as the line was sung, not some fixed length.
        #expect(nodes.map(\.duration) == [5_100, 5_340, 2_340])
    }

    @Test("the text of each line is the text of its clip")
    func carriesTheText() throws {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        for (node, line) in zip(shell.effects.nodes, Self.sample) {
            let value = try #require(node.values[TextEffect.Param.text])
            #expect(value == .text(line.text))
        }
    }

    @Test("every clip is a text effect")
    func placesTextEffects() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        #expect(shell.effects.nodes.allSatisfy { $0.type == TextEffect.descriptor.type })
    }

    /// A clip named "Text 7" says nothing about which line it holds, and
    /// thirty-eight of them are a track nobody can read. The line is the name.
    @Test("a clip is named after the line it holds")
    func namesClipsAfterTheirText() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        #expect(shell.effects.nodes.map(\.name) == Self.sample.map(\.text))
    }

    @Test("a long line's name is shortened, and still says which line it is")
    func shortensLongNames() {
        let shell = EditorShellModel()
        let long = String(repeating: "あ", count: 60)

        shell.importLyrics([Self.line(long, 0, 2000)])

        let name = shell.effects.nodes[0].name
        #expect(name.count < long.count)
        #expect(long.hasPrefix(String(name.prefix(10))))
    }

    // ─── Where they land ─────────────────────────────────────────────────────

    @Test("the clips go on a track of their own")
    func placesOnItsOwnTrack() throws {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        let track = try #require(shell.effects.tracks.first { !$0.nodes.isEmpty })
        #expect(track.nodes.count == 3)
        #expect(track.name == "Lyrics")
    }

    /// Importing twice — a second language, or a corrected pass — should not
    /// pile the new lines on top of the old ones in the same lane, where they
    /// would overlap and be unpickable.
    @Test("importing again uses a new track")
    func secondImportGetsItsOwnTrack() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)
        shell.importLyrics(Self.sample)

        let populated = shell.effects.tracks.filter { !$0.nodes.isEmpty }
        #expect(populated.count == 2)
        #expect(populated.allSatisfy { $0.nodes.count == 3 })
    }

    @Test("an existing project keeps its own tracks")
    func doesNotDisturbExistingWork() {
        let shell = EditorShellModel()
        shell.addEffect(EmitterEffect.descriptor, at: 1000)
        let before = shell.effects.nodes.count

        shell.importLyrics(Self.sample)

        #expect(shell.effects.nodes.count == before + 3)
        #expect(shell.effects.nodes.contains { $0.type == EmitterEffect.descriptor.type })
    }

    // ─── Undo ────────────────────────────────────────────────────────────────

    /// The test that justifies coalescing. Thirty-eight clips placed one at a
    /// time leave thirty-eight undo entries, so taking the import back is
    /// thirty-eight keystrokes — and each one shows a half-imported song.
    @Test("the whole import is one undo step")
    func importIsOneUndoStep() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)
        #expect(shell.effects.nodes.count == 3)

        shell.undo()

        #expect(shell.effects.nodes.isEmpty)
    }

    @Test("undoing an import leaves the work that was there")
    func undoKeepsEarlierWork() {
        let shell = EditorShellModel()
        shell.addEffect(EmitterEffect.descriptor, at: 1000)

        shell.importLyrics(Self.sample)
        shell.undo()

        #expect(shell.effects.nodes.count == 1)
        #expect(shell.effects.nodes[0].type == EmitterEffect.descriptor.type)
    }

    // ─── Size ────────────────────────────────────────────────────────────────

    /// The **transform's scale**, not the font size.
    ///
    /// `TextSprite.rawPath` hashes the font size into each glyph's path, so
    /// every size tried mints a fresh texture for every character — 111 of them
    /// in one song. A scale is one `_V` command and the texture is unchanged.
    @Test("a size reaches every clip as its scale")
    func appliesTheScale() {
        let shell = EditorShellModel()
        shell.lyricScale = 0.6

        shell.importLyrics(Self.sample)

        for node in shell.effects.nodes {
            #expect(node.transform[value: .scaleX] == 0.6)
            #expect(node.transform[value: .scaleY] == 0.6)
        }
    }

    /// One knob, both axes. Lyrics are read, not stretched — an author who
    /// wants one axis has the inspector, and offering two fields here would be
    /// two numbers to keep in step for a case nobody asked for.
    @Test("both axes get the same number")
    func scaleIsUniform() {
        let shell = EditorShellModel()
        shell.lyricScale = 1.4

        shell.importLyrics(Self.sample)

        let node = shell.effects.nodes[0]
        #expect(node.transform[value: .scaleX] == node.transform[value: .scaleY])
    }

    @Test("the default leaves the clip at full size")
    func defaultScaleIsUntouched() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        // Whatever a placed text clip is normally, that is what this is: the
        // size is a knob, not something the import decides.
        #expect(shell.effects.nodes[0].transform[value: .scaleX] == 1)
    }

    @Test("a line placed on its own gets the scale too")
    func singleLineGetsTheScale() {
        let shell = EditorShellModel()
        shell.lyricScale = 0.5

        shell.importLyricLine(Self.sample[0])

        #expect(shell.effects.nodes[0].transform[value: .scaleX] == 0.5)
    }

    // ─── Telling the rest of the app ─────────────────────────────────────────

    /// Found by a *span* test, not by any of the sixteen tests written for the
    /// import itself — none of them looked at the revision.
    ///
    /// `beginGesture`/`endGesture` coalesce the undo entry and hold evaluation
    /// until the batch is in, and it is tempting to think that is the whole
    /// bracket. It is not: `endGesture` only re-evaluates. Without
    /// `effectsChanged` the revision stayed at **zero** through the entire
    /// import — so the canvas was never told there were new sprites, the title
    /// bar never showed unsaved changes, and every revision-keyed cache went on
    /// serving a pre-import answer.
    @Test("the import tells the rest of the app that the document moved")
    func importBumpsTheRevision() {
        let shell = EditorShellModel()
        let before = shell.effectsRevision

        shell.importLyrics(Self.sample)

        #expect(shell.effectsRevision > before)
    }

    @Test("the import marks the project unsaved")
    func importMarksUnsaved() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        #expect(shell.hasUnsavedChanges)
    }

    @Test("importing nothing does not mark the project unsaved")
    func emptyImportLeavesItClean() {
        let shell = EditorShellModel()

        shell.importLyrics([])

        #expect(!shell.hasUnsavedChanges)
    }

    // ─── Presets ─────────────────────────────────────────────────────────────

    /// Thirty-eight clips with every animation parameter at zero are
    /// thirty-eight captions. A preset is only a bag of values, so this costs
    /// nothing and is the difference between subtitles and motion graphics.
    @Test("a preset's values reach every clip")
    func appliesThePreset() throws {
        let shell = EditorShellModel()
        let preset = try #require(TextEffect.presets.first { $0.id == "typewriter" })

        shell.importLyrics(Self.sample, preset: preset)

        for node in shell.effects.nodes {
            // Whatever the preset says about staggering, each clip got it.
            #expect(node.values[TextEffect.Param.stagger] == preset.values[TextEffect.Param.stagger])
        }
    }

    @Test("a preset does not overwrite the line's own text")
    func presetLeavesTextAlone() throws {
        let shell = EditorShellModel()
        let preset = try #require(TextEffect.presets.first)

        shell.importLyrics(Self.sample, preset: preset)

        #expect(shell.effects.nodes[0].values[TextEffect.Param.text] == .text(Self.sample[0].text))
    }

    /// A preset carries its own duration for a placed clip, and that is right
    /// for a placement and wrong here: a lyric line lasts as long as it was
    /// sung, and stretching it to the preset's length would slide every line
    /// off the words it belongs to.
    @Test("a preset's duration does not override the sung timing")
    func presetDurationDoesNotWin() throws {
        let shell = EditorShellModel()
        let preset = try #require(TextEffect.presets.first)

        shell.importLyrics(Self.sample, preset: preset)

        #expect(shell.effects.nodes.map(\.duration) == [5_100, 5_340, 2_340])
    }

    // ─── Degenerate input ────────────────────────────────────────────────────

    @Test("importing nothing changes nothing")
    func emptyImportIsANoOp() {
        let shell = EditorShellModel()

        shell.importLyrics([])

        #expect(shell.effects.tracks.allSatisfy { $0.nodes.isEmpty })
        // And leaves no empty lane behind either.
        #expect(shell.effects.tracks.isEmpty)
    }

    @Test("a line with no duration still lands as something draggable")
    func zeroDurationLineIsGivenALength() {
        let shell = EditorShellModel()

        // The engine can report a glyph whose range is a single instant.
        shell.importLyrics([Self.line("あ", 5000, 5000)])

        // A zero-length clip cannot be grabbed, and `TextEffect` draws nothing
        // for one: it guards on `context.duration > 0`.
        #expect(shell.effects.nodes[0].duration > 0)
    }

    // ─── Seeds ───────────────────────────────────────────────────────────────

    /// Two clips sharing a seed animate identically wherever the effect is
    /// random — a `Random` stagger, or the scatter of an `Explode` exit — and
    /// consecutive lines are exactly the pair somebody would notice.
    @Test("no two clips share a seed")
    func seedsAreDistinct() {
        let shell = EditorShellModel()

        shell.importLyrics(Self.sample)

        let seeds = shell.effects.nodes.map(\.seed)
        #expect(Set(seeds).count == seeds.count)
    }
}

/// Running a transcription from the shell.
///
/// The transcriber lives in the platform layer and the shell does not import
/// it, so it arrives as a handler the app fills in — the same route the video
/// export already takes, and for the same reason.
@MainActor
@Suite("Transcribing lyrics")
struct TranscribeLyricsTests {
    @Test("nothing can be transcribed without a handler")
    func needsAHandler() {
        let shell = EditorShellModel()

        #expect(!shell.canTranscribeLyrics)
    }

    @Test("a handler and a track make it available")
    func availableWithBoth() {
        let shell = EditorShellModel()
        shell.lyricTranscriptionHandler = { _, _ in [] }

        #expect(shell.canTranscribeLyrics)
    }

    @Test("transcribed words arrive as lines, ready to place")
    func producesLines() async {
        let shell = EditorShellModel()
        shell.lyricTranscriptionHandler = { _, _ in
            transcribed([("落", 0, 300), ("ち", 300, 540), ("逆", 2000, 2300)])
        }

        await shell.transcribeLyrics(locale: "ja-JP")

        #expect(shell.lyricLines.count == 2)
        #expect(shell.lyricLines[0].text == "落ち")
        // Nothing is placed until somebody asks: a transcription is a draft,
        // and thirty-eight clips appearing unbidden is not a draft.
        #expect(shell.effects.nodes.isEmpty)
    }

    @Test("a failure is reported rather than read as a quiet song")
    func reportsFailure() async {
        struct Boom: Error, CustomStringConvertible { var description: String { "no model" } }
        let shell = EditorShellModel()
        shell.lyricTranscriptionHandler = { _, _ in throw Boom() }

        await shell.transcribeLyrics(locale: "ja-JP")

        #expect(shell.lyricError != nil)
        #expect(shell.lyricLines.isEmpty)
    }

    @Test("a new run clears the last one's error")
    func clearsPreviousError() async {
        struct Boom: Error {}
        let shell = EditorShellModel()
        shell.lyricTranscriptionHandler = { _, _ in throw Boom() }
        await shell.transcribeLyrics(locale: "ja-JP")
        #expect(shell.lyricError != nil)

        shell.lyricTranscriptionHandler = { _, _ in transcribed([("あ", 0, 300)]) }
        await shell.transcribeLyrics(locale: "ja-JP")

        #expect(shell.lyricError == nil)
        #expect(shell.lyricLines.count == 1)
    }

    @Test("the locale asked for is the locale passed on")
    func passesTheLocale() async {
        let shell = EditorShellModel()
        let seen = LocaleBox()
        shell.lyricTranscriptionHandler = { _, locale in
            seen.value = locale
            return []
        }

        await shell.transcribeLyrics(locale: "ja-JP")

        #expect(seen.value == "ja-JP")
    }

    /// A transcription takes seconds, and a window with no sign of it is a
    /// window that looks hung — the same reason the video export reports
    /// progress.
    @Test("it says while it is running, and stops saying when it is done")
    func reportsWhileRunning() async {
        let shell = EditorShellModel()
        #expect(!shell.isTranscribingLyrics)

        shell.lyricTranscriptionHandler = { _, _ in transcribed([("あ", 0, 300)]) }
        await shell.transcribeLyrics(locale: "ja-JP")

        #expect(!shell.isTranscribingLyrics)
    }

    @Test("the placed lines are the ones that were shown")
    func placesWhatWasTranscribed() async {
        let shell = EditorShellModel()
        shell.lyricTranscriptionHandler = { _, _ in
            transcribed([("落", 0, 300), ("ち", 300, 540), ("逆", 2000, 2300)])
        }
        await shell.transcribeLyrics(locale: "ja-JP")

        shell.importLyrics(shell.lyricLines)

        #expect(shell.effects.nodes.count == 2)
        #expect(shell.effects.nodes.map(\.name) == shell.lyricLines.map(\.text))
    }

    @Test("the languages are asked of the app, not guessed")
    func offersTheAppsLocales() async {
        let shell = EditorShellModel()
        shell.lyricLocalesHandler = { (["en-US", "ja-JP", "es-ES"], ["ja-JP"]) }

        let (all, installed) = await shell.lyricLocales()

        #expect(all.count == 3)
        // Installed ones are worth telling apart: those start in seconds, and
        // anything else downloads a model first.
        #expect(installed == ["ja-JP"])
    }

    @Test("with no handler there are no languages to offer")
    func noLocalesWithoutHandler() async {
        let shell = EditorShellModel()

        let (all, installed) = await shell.lyricLocales()

        #expect(all.isEmpty)
        #expect(installed.isEmpty)
    }

    @Test("editing the threshold regroups without transcribing again")
    func regroupsWithoutRerunning() async {
        let shell = EditorShellModel()
        let runs = CountBox()
        shell.lyricTranscriptionHandler = { _, _ in
            runs.value += 1
            // 150ms apart: one line at the 200ms default, two once the
            // threshold is tightened below the gap.
            return transcribed([("あ", 0, 200), ("い", 350, 550)])
        }
        await shell.transcribeLyrics(locale: "ja-JP")
        #expect(shell.lyricLines.count == 1)

        shell.regroupLyrics(gapThreshold: 100)

        #expect(shell.lyricLines.count == 2)
        // The song was read once. Re-transcribing to change a number would
        // cost seconds for an answer already in hand.
        #expect(runs.value == 1)
    }
}

/// Placing lines one at a time, so each can carry its own movement.
///
/// The reason this exists rather than only `Place All`: a chorus wants a
/// different entrance from a verse, and giving thirty-eight clips the same
/// preset and then fixing them one by one in the inspector is the work this
/// feature was supposed to remove.
@MainActor
@Suite("Placing lyric lines individually")
struct PlaceOneLyricTests {
    private static func line(_ text: String, _ start: Double) -> LyricTranscription.Line {
        LyricTranscription.Line(text: text, start: start, end: start + 1500)
    }

    @Test("one line places one clip")
    func placesOne() {
        let shell = EditorShellModel()

        shell.importLyricLine(Self.line("a", 1000))

        #expect(shell.effects.nodes.count == 1)
        #expect(shell.effects.nodes[0].startTime == 1000)
    }

    @Test("a placed line is marked, so a second pass shows what is done")
    func marksWhatIsPlaced() {
        let shell = EditorShellModel()
        let first = Self.line("a", 1000)
        let second = Self.line("b", 5000)

        shell.importLyricLine(first)

        #expect(shell.placedLyricLines.contains(first.id))
        #expect(!shell.placedLyricLines.contains(second.id))
    }

    /// The whole point: two lines, two movements.
    @Test("each line can carry a different movement")
    func differentPresetsPerLine() throws {
        let shell = EditorShellModel()
        let typewriter = try #require(TextEffect.presets.first { $0.id == "typewriter" })
        let drop = try #require(TextEffect.presets.first { $0.id == "drop" })

        shell.importLyricLine(Self.line("a", 1000), preset: typewriter)
        shell.importLyricLine(Self.line("b", 5000), preset: drop)

        let nodes = shell.effects.nodes
        #expect(nodes.count == 2)
        // Whatever the two presets disagree about, the clips disagree too.
        #expect(nodes[0].values != nodes[1].values)
    }

    @Test("regrouping forgets what was placed, since the lines are new")
    func regroupClearsMarks() async {
        let shell = EditorShellModel()
        shell.lyricTranscriptionHandler = { _, _ in
            transcribed([("a", 0, 200), ("b", 350, 550)])
        }
        await shell.transcribeLyrics(locale: "ja-JP")
        shell.importLyricLine(shell.lyricLines[0])
        #expect(!shell.placedLyricLines.isEmpty)

        shell.regroupLyrics(gapThreshold: 100)

        // The lines are different objects now, so a mark would tick a row that
        // was never placed.
        #expect(shell.placedLyricLines.isEmpty)
    }

    @Test("discarding forgets what was placed")
    func discardClearsMarks() {
        let shell = EditorShellModel()
        shell.importLyricLine(Self.line("a", 1000))

        shell.clearLyrics()

        #expect(shell.placedLyricLines.isEmpty)
        // The clip stays: it is on the timeline now, and discarding the draft
        // is not the same as undoing the placement.
        #expect(shell.effects.nodes.count == 1)
    }

    @Test("placing one line is one undo step")
    func oneLineIsOneUndoStep() {
        let shell = EditorShellModel()

        shell.importLyricLine(Self.line("a", 1000))
        shell.undo()

        #expect(shell.effects.nodes.isEmpty)
    }
}

/// Words in the shape a transcription returns them.
///
/// At file scope, not on the suite: it is called from inside a `@Sendable`
/// closure, which does not run on the main actor.
private func transcribed(_ pieces: [(String, Double, Double)]) -> [LyricTranscription.Word] {
    pieces.map {
        LyricTranscription.Word(text: $0.0, start: $0.1, end: $0.2, confidence: 0.9)
    }
}

/// Somewhere for a `@Sendable` closure to record what it saw.
private final class LocaleBox: @unchecked Sendable {
    var value: String?
}

private final class CountBox: @unchecked Sendable {
    var value = 0
}

/// The span the timeline draws against, and what asking for it costs.
///
/// Found with `sample` on the running app after eight hypotheses had been
/// measured and killed from outside it: `fullRange` was burning **895 of every
/// 1000 milliseconds** — 720 calls a second, sixteen per frame — while the
/// whole of drawing used eight. Every call walked all 84 nodes, and asked
/// `duration(of:on:)` about each, which looked each one up with a **linear
/// search** through every track. Quadratic, so placing lyrics did not cause it:
/// it took the project from 35 nodes to 84 and made it visible.
@MainActor
@Suite("Timeline span cost")
struct TimelineSpanTests {
    private func loaded(nodes: Int) -> EditorShellModel {
        let shell = EditorShellModel()
        let lines = (0..<nodes).map { index in
            LyricTranscription.Line(
                text: "line \(index)",
                start: Double(index) * 2000,
                end: Double(index) * 2000 + 1500,
            )
        }
        shell.importLyrics(lines)
        return shell
    }

    @Test("the span is the same answer however many times it is asked")
    func spanIsStable() {
        let shell = loaded(nodes: 20)

        let first = shell.playedTimeRange
        let second = shell.playedTimeRange

        #expect(first == second)
    }

    @Test("the span covers every clip")
    func spanCoversEverything() throws {
        let shell = loaded(nodes: 20)

        let span = try #require(shell.playedTimeRange)

        #expect(span.lowerBound <= 0)
        // The last clip starts at 38000 and runs 1500.
        #expect(span.upperBound >= 39_500)
    }

    /// The guard that pins the fix: asking repeatedly has to cost about what
    /// asking once does. Without a cache this was 84 linear lookups per call.
    @Test("asking a hundred times costs about what asking once does")
    func repeatedAsksAreCheap() {
        let shell = loaded(nodes: 84)
        let clock = ContinuousClock()

        // Warm, so the first evaluation is not being measured.
        _ = shell.playedTimeRange

        let started = clock.now
        for _ in 0..<100 { _ = shell.playedTimeRange }
        let elapsed = clock.now - started

        // A hundred cached reads are microseconds. Uncached they were over a
        // millisecond each, which is what sixteen per frame turned into 20ms.
        #expect(elapsed < .milliseconds(20), "100 reads took \(elapsed)")
    }

    @Test("an edit changes the answer")
    func editInvalidatesTheSpan() throws {
        let shell = loaded(nodes: 5)
        let before = try #require(shell.playedTimeRange)

        shell.importLyrics([
            LyricTranscription.Line(text: "later", start: 90_000, end: 92_000),
        ])

        let after = try #require(shell.playedTimeRange)
        #expect(after.upperBound > before.upperBound)
    }

    @Test("an empty document has no span")
    func emptyDocumentHasNoSpan() {
        #expect(EditorShellModel().playedTimeRange == nil)
    }
}
