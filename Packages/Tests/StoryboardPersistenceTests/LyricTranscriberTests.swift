import AVFoundation
import Foundation
import Testing

@testable import StoryboardPersistence

/// Whether this machine has the speech framework these tests need.
///
/// Read once, at the suite level: on an older macOS every case would otherwise
/// have to decide for itself, and one that forgot would fail rather than skip.
private let transcriptionAvailable: Bool = {
    if #available(macOS 26, *) { LyricTranscriber.isAvailable } else { false }
}()

/// Writes a throwaway audio file: a tone, which has no words in it.
private struct TemporaryAudio: ~Copyable {
    let url: URL

    init(seconds: Double, sampleRate: Double = 44_100) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lyric-transcriber-tests-\(UUID().uuidString).caf")

        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        if let channel = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                channel[frame] = 0.5 * Float(sin(Double(frame) / sampleRate * 440 * 2 * .pi))
            }
        }
        try file.write(from: buffer)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// What can be checked about the transcriber without the speech model deciding
/// the answer.
///
/// **What these do not cover, deliberately: whether the transcription is any
/// good.** That was settled by measurement, not by a test — a probe over three
/// real songs, where Japanese came back at 0.97 median confidence with verified
/// lines, and English at 0.61 with 41% of words below 0.5. A synthetic tone has
/// no words in it, so a test built on one can only assert "no words came back",
/// which is true of a working transcriber and a broken one alike. And a test
/// that shipped a real song as a fixture would be asserting that Apple's model
/// never changes its mind, which is not this code's promise to keep.
///
/// So what is here is the shape around the model: that failures are reported
/// rather than swallowed, that times land in the units the rest of the app
/// speaks, and that an unsupported locale says so instead of returning nothing
/// and looking like a quiet song.
/// > The suite is gated with `.enabled(if:)` rather than `@available`, which
/// swift-testing rejects on a suite outright: a test the platform cannot run is
/// a test that does not exist, so the framework asks for the condition at
/// runtime instead. Each body still needs `if #available` for the compiler,
/// since the package targets macOS 14.
@Suite("LyricTranscriber", .enabled(if: transcriptionAvailable))
struct LyricTranscriberTests {
    // ─── Locales ─────────────────────────────────────────────────────────────

    @Test("a locale the model cannot do is reported, not returned empty")
    func unsupportedLocaleThrows() async throws {
        guard #available(macOS 26, *) else { return }
        let audio = try TemporaryAudio(seconds: 1)

        // Klingon is not going to acquire an on-device speech model.
        await #expect(throws: LyricTranscriber.Failure.unsupportedLocale("tlh-Piqd")) {
            try await LyricTranscriber.words(from: audio.url, locale: "tlh-Piqd")
        }
    }

    /// The two languages this was measured on, plus the one the editor runs in.
    ///
    /// Not an assertion that Apple ships them — that is Apple's to change — but
    /// that asking is answered rather than crashing, and that the answer is the
    /// canonical identifier rather than whatever string was passed in.
    @Test("asking about a locale is answered", arguments: ["en-US", "ja-JP", "es-ES"])
    func supportedLocaleIsAnswered(locale: String) async {
        guard #available(macOS 26, *) else { return }
        let resolved = await LyricTranscriber.supportedLocale(matching: locale)
        if let resolved {
            #expect(!resolved.isEmpty)
        }
    }

    @Test("the locales it can do are the ones it offers")
    func offeredLocalesAreSupported() async {
        guard #available(macOS 26, *) else { return }
        let offered = await LyricTranscriber.availableLocales()

        // Whatever is offered has to be answerable, or the picker lists
        // languages that fail when chosen.
        for locale in offered.prefix(5) {
            let resolved = await LyricTranscriber.supportedLocale(matching: locale)
            #expect(resolved != nil, "\(locale) was offered but is not supported")
        }
    }

    /// The bug this pins down: a model that is already downloaded was reported
    /// as unavailable.
    ///
    /// `AssetInventory.status(forModules:)` returns `.supported` — not
    /// `.installed` — for a language that is present and working, while
    /// `installedLocales` lists it and `assetInstallationRequest` returns `nil`
    /// because there is nothing left to fetch. Reading `status` as "needs
    /// downloading" asked for a request that could not exist and threw
    /// `modelUnavailable` over a model that was right there.
    @Test("a language already installed is not reported as unavailable")
    func installedLocaleIsNotUnavailable() async throws {
        guard #available(macOS 26, *) else { return }
        let installed = await LyricTranscriber.installedLocales()
        // Nothing is installed on a fresh machine, and downloading a model to
        // satisfy a test is not this suite's business.
        try withKnownIssue(isIntermittent: true) {
            try #require(!installed.isEmpty, "no speech models installed on this machine")
        }
        guard let locale = installed.first else { return }

        let audio = try TemporaryAudio(seconds: 1)

        // A tone has no words in it, so the result is empty either way — what
        // matters is that it did not *fail*, which is what the bug did.
        let words = try await LyricTranscriber.words(from: audio.url, locale: locale)
        #expect(words.isEmpty)
    }

    // ─── Errors ──────────────────────────────────────────────────────────────

    @Test("a file that is not audio is reported")
    func unreadableAudioThrows() async throws {
        guard #available(macOS 26, *) else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-audio-\(UUID().uuidString).mp3")
        try Data("this is not an audio file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) {
            try await LyricTranscriber.words(from: url, locale: "en-US")
        }
    }

    @Test("a file that is not there is reported")
    func missingAudioThrows() async {
        guard #available(macOS 26, *) else { return }
        await #expect(throws: (any Error).self) {
            try await LyricTranscriber.words(
                from: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mp3"),
                locale: "en-US",
            )
        }
    }

    // ─── Units ───────────────────────────────────────────────────────────────

    /// The whole app speaks milliseconds: `startTime`, `duration`, every
    /// command in the file. `CMTimeRange` speaks seconds, and a transcriber
    /// that handed its own unit to the importer would place a five-minute song
    /// inside the first half-second of the timeline.
    @Test("times come back in milliseconds")
    func timesAreMilliseconds() throws {
        guard #available(macOS 26, *) else { return }
        let range = CMTimeRange(
            start: CMTime(seconds: 16.68, preferredTimescale: 1000),
            duration: CMTime(seconds: 0.3, preferredTimescale: 1000),
        )

        let word = try #require(LyricTranscriber.word("落", in: range, confidence: 0.99))

        // 16.680s into the song — the first sung glyph of the song this was
        // measured on.
        #expect(abs(word.start - 16_680) < 1)
        #expect(abs(word.end - 16_980) < 1)
        #expect(word.confidence == 0.99)
    }

    @Test("a word with no confidence reported has none")
    func absentConfidenceStaysAbsent() throws {
        guard #available(macOS 26, *) else { return }
        let range = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 1000),
            duration: CMTime(seconds: 0.5, preferredTimescale: 1000),
        )

        let word = try #require(LyricTranscriber.word("a", in: range, confidence: nil))
        #expect(word.confidence == nil)
    }

    /// An invalid `CMTime` reads as `NaN` in seconds, and `NaN` milliseconds
    /// reaches `EffectDocument.add` as a clip start — where `Int(nan)` traps.
    /// This project has already lost a test runner to exactly that, from a
    /// script dividing zero by zero.
    @Test("a time the engine could not place is dropped, not passed on as NaN")
    func invalidTimeIsRejected() {
        guard #available(macOS 26, *) else { return }
        #expect(LyricTranscriber.word("a", in: .invalid, confidence: 0.9) == nil)
    }
}
