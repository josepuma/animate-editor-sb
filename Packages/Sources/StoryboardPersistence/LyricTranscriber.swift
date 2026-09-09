import AVFoundation
import Foundation
import Speech
import StoryboardCore

/// Transcribes sung words out of a track, on device.
///
/// The platform half of ``LyricTranscription``: Core cannot import `Speech`, so
/// this is what fills its seam. Nothing here decides what to do with the words
/// — grouping them into lines is Core's, and testable without a model.
///
/// **On device, and free.** `SpeechAnalyzer` (macOS 26) has no server fallback
/// and the model is held by the OS rather than bundled, so this adds nothing to
/// the app's size or its dependencies. Measured on an M-series Mac: a
/// five-minute song in 2.1 seconds once the model is warm, 150× realtime.
///
/// **What it is like on singing**, measured over three real tracks, because
/// Apple documents nothing about it and no public benchmark covers it:
///
/// | | median confidence | below 0.5 |
/// |---|---|---|
/// | Japanese (`ja-JP`) | 0.97 | 6% |
/// | English (`en-US`) | 0.61–0.72 | 27–41% |
///
/// Japanese comes back glyph by glyph and is nearly publishable; English comes
/// back word by word and needs a correction pass. Either way the confidence is
/// the useful part — it says *which* words to look at.
///
/// > Gated at macOS 26 rather than raising the package's own minimum, which is
/// 14: everything else here runs on 14 and has no reason to stop. The importer
/// asks ``isAvailable`` and says so, which is a language picker with nothing in
/// it rather than an app that will not launch.
@available(macOS 26, *)
public enum LyricTranscriber {
    /// Why a transcription could not be produced.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// No on-device model exists for this language.
        case unsupportedLocale(String)
        /// The model is not installed and could not be downloaded.
        case modelUnavailable(String)

        public var description: String {
            switch self {
            case let .unsupportedLocale(locale):
                "No on-device speech model for \(locale)."
            case let .modelUnavailable(locale):
                "The speech model for \(locale) could not be installed."
            }
        }
    }

    // ─── Locales ─────────────────────────────────────────────────────────────

    /// Whether transcription can run on this machine at all.
    ///
    /// Asked before a language picker is drawn: a list of languages over a
    /// framework that cannot answer is a control that fails on use, and the
    /// honest version of that is a panel saying transcription is unavailable.
    public static var isAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    /// Every language the model can transcribe, as identifiers.
    ///
    /// Asked of the framework rather than listed here: the set grows with the
    /// OS, and a hard-coded list would be a picker that lies in both
    /// directions.
    public static func availableLocales() async -> [String] {
        await SpeechTranscriber.supportedLocales.map(\.identifier)
    }

    /// The languages whose models are already on the machine.
    ///
    /// Worth telling apart from ``availableLocales()`` in the UI: one of these
    /// starts transcribing in seconds, and any other language downloads a model
    /// first.
    public static func installedLocales() async -> [String] {
        await SpeechTranscriber.installedLocales.map(\.identifier)
    }

    /// The identifier the model actually uses for a language, or `nil`.
    ///
    /// A locale is asked about before anything is downloaded, so the UI can
    /// grey out a language instead of offering it and failing.
    public static func supportedLocale(matching locale: String) async -> String? {
        await SpeechTranscriber
            .supportedLocale(equivalentTo: Locale(identifier: locale))?
            .identifier
    }

    // ─── Transcribing ────────────────────────────────────────────────────────

    /// The words in a track, with the moment each was sung.
    ///
    /// - Parameter progress: called with the model download's progress the
    ///   first time a language is used, and not at all afterwards. The download
    ///   is the only part long enough to need a bar; the transcription itself
    ///   is seconds.
    public static func words(
        from audio: URL,
        locale: String,
        progress: (@Sendable (Progress) -> Void)? = nil,
    ) async throws -> [LyricTranscription.Word] {
        guard let resolved = await supportedLocale(matching: locale) else {
            throw Failure.unsupportedLocale(locale)
        }

        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: resolved),
            transcriptionOptions: [],
            // No volatile results: nothing is watching this arrive, and asking
            // for partial passes would mean sifting out the ones that were
            // later revised.
            reportingOptions: [],
            // The two attributes this exists for. Without the time range there
            // is nothing to place a clip at, and without the confidence there
            // is no way to say which words to check.
            attributeOptions: [.audioTimeRange, .transcriptionConfidence],
        )

        try await install(transcriber, locale: resolved, progress: progress)

        // The file-based initialiser. It decodes, resamples and chunks the
        // audio itself — a hand-rolled `AVAudioConverter` feeding an
        // `AsyncStream` of `AnalyzerInput` reimplements all of it, which is
        // what reading the conference session instead of the SDK produced the
        // first time.
        let file = try AVAudioFile(forReading: audio)
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: file,
            modules: [transcriber],
            finishAfterFile: true,
        )

        // Collected while the analyzer streams rather than after it finishes:
        // its results sequence is consumed as it produces, and starting the
        // analysis first would mean racing to attach.
        let collector = Task { () -> [LyricTranscription.Word] in
            var words: [LyricTranscription.Word] = []
            for try await result in transcriber.results {
                words += self.words(in: result.text)
            }
            return words
        }

        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }

    // ─── Reading the result ──────────────────────────────────────────────────

    /// Pulls the timed words out of one transcription result.
    ///
    /// A result's text is an `AttributedString` whose runs carry the attributes
    /// that were asked for, so a run is a word — or in a script transcribed
    /// glyph by glyph, a glyph.
    static func words(in text: AttributedString) -> [LyricTranscription.Word] {
        text.runs.compactMap { run in
            let piece = String(text[run.range].characters)
            guard !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            // A run with no time range cannot be placed, and a clip needs a
            // time more than the storyboard needs the word.
            guard let range = run.audioTimeRange else { return nil }
            return word(piece, in: range, confidence: run.transcriptionConfidence)
        }
    }

    /// One word, in the units the rest of the app speaks.
    ///
    /// Milliseconds, because `startTime`, `duration` and every command in the
    /// file are milliseconds — handing seconds to the importer would place a
    /// five-minute song inside the first half second of the timeline.
    ///
    /// `nil` when the engine could not place the word: an invalid `CMTime`
    /// reads as `NaN` in seconds, and a `NaN` start reaches `Int()` further
    /// down, where it does not throw — it **traps**. This project has already
    /// lost a test runner to that exact conversion.
    static func word(
        _ text: String,
        in range: CMTimeRange,
        confidence: Double?,
    ) -> LyricTranscription.Word? {
        let start = range.start.seconds
        let end = range.end.seconds
        guard start.isFinite, end.isFinite, end >= start else { return nil }

        return LyricTranscription.Word(
            text: text,
            start: start * 1000,
            end: end * 1000,
            confidence: confidence,
        )
    }

    // ─── The model ───────────────────────────────────────────────────────────

    /// Makes sure the language's model is on the machine.
    ///
    /// The download is the slow part of a first run and the only part worth a
    /// progress bar; afterwards this returns immediately.
    ///
    /// > **`AssetInventory.status(forModules:)` is not the question to ask.**
    /// Measured on a Mac where Japanese was already downloaded and working, it
    /// reports `.supported` — not `.installed` — while
    /// `SpeechTranscriber.installedLocales` lists `ja_JP` and
    /// `assetInstallationRequest` returns `nil` because there is nothing left
    /// to fetch. Reading `status` as "needs downloading" therefore asked for a
    /// request that could not exist and failed over a model that was right
    /// there. `installedLocales` is the answer that matches reality.
    private static func install(
        _ transcriber: SpeechTranscriber,
        locale: String,
        progress: (@Sendable (Progress) -> Void)?,
    ) async throws {
        guard await !isInstalled(locale) else { return }

        guard let request = try await AssetInventory
            .assetInstallationRequest(supporting: [transcriber])
        else {
            // Not installed and nothing to install: out of reach for a reason
            // this cannot see, which is worth saying rather than transcribing
            // silence.
            throw Failure.modelUnavailable(locale)
        }

        progress?(request.progress)
        try await request.downloadAndInstall()

        guard await isInstalled(locale) else {
            throw Failure.modelUnavailable(locale)
        }
    }

    /// Whether a language's model is on the machine already.
    ///
    /// Compared through `Locale` rather than as strings: the framework answers
    /// in its own spelling — `ja_JP` where the app asked for `ja-JP` — and a
    /// string comparison would download a model that was already there, every
    /// single time.
    private static func isInstalled(_ locale: String) async -> Bool {
        let wanted = Locale(identifier: locale).identifier(.icu)
        return await SpeechTranscriber.installedLocales
            .contains { $0.identifier(.icu) == wanted }
    }
}
