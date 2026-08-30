import Foundation
import StoryboardCore
import StoryboardPersistence

/// Playback clock and renderer statistics.
///
/// When the beatmap has audio, the clock follows the audio device: a display
/// link and an audio device drift apart, and a storyboard driven by anything
/// but the audio slides out of sync with the music. Without audio it falls back
/// to accumulating frame deltas.
@MainActor
@Observable
public final class PlaybackModel {
    /// Current position, in milliseconds.
    public private(set) var currentTime: Double = 0
    public private(set) var isPlaying = false
    /// How far playback runs: the length of the track.
    public private(set) var duration: Double = 1

    /// The span the timeline shows.
    ///
    /// A storyboard is not bound to its track: an intro can begin before the
    /// first note and a fade can end after the last. Those are exactly the
    /// commands an editor has to show — clipping the ruler to the audio would
    /// hide the sprites whose timing is hardest to get right. So the timeline
    /// covers whichever span is wider while the transport still stops with the
    /// music.
    public private(set) var timelineRange: ClosedRange<Double> = 0...1

    public private(set) var spriteCount = 0
    public private(set) var drawnCount = 0
    public private(set) var framesPerSecond: Double = 0
    public private(set) var status: Status = .loading
    public private(set) var hasAudio = false

    /// The canvas fills the window, hiding the panels and timeline.
    ///
    /// Full screen for the storyboard rather than for the window: the point is
    /// to see the picture without the editor around it, which a full-screen
    /// window with all its panels still showing does not give.
    public var isCanvasFullScreen = false

    /// Timing and metadata from the beatmap, when it has a readable `.osu`.
    public private(set) var timing: BeatmapTimingData?

    /// The prepared sprites, for panels that describe the storyboard's
    /// contents rather than draw them.
    public private(set) var sprites: [PreparedSprite] = []

    /// Image paths the storyboard references that are not on disk.
    public private(set) var missingImagePaths: Set<String> = []

    /// Peaks for drawing the audio behind the timeline, once extracted.
    public private(set) var waveform: Waveform?

    public var breaks: [BreakPeriod] { timing?.breaks ?? [] }

    /// Kiai sections, clamped to the track — the parser leaves a section that
    /// is still on at the last timing point open past the end.
    public var kiaiSections: [KiaiSection] {
        (timing?.kiaiSections ?? []).map { section in
            KiaiSection(
                startTime: section.startTime,
                endTime: min(section.endTime, duration),
            )
        }
    }

    /// Set when audio was expected but could not be played. Playback continues
    /// on the synthetic clock.
    public private(set) var audioWarning: String?

    private let audio = AudioPlayer()

    public enum Status: Equatable, Sendable {
        case loading
        case ready(String)
        case failed(String)

        public var message: String {
            switch self {
            case .loading: "Loading…"
            case let .ready(name): name
            case let .failed(reason): reason
            }
        }

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        public var isLoading: Bool { self == .loading }
    }

    public init() {}

    // ─── Content ─────────────────────────────────────────────────────────────

    /// The storyboard has started loading.
    public func contentLoading() {
        status = .loading
    }

    /// Releases the storyboard and stops the audio.
    ///
    /// Leaving the editor has to actually let go: without this the track keeps
    /// playing behind the project browser and the sprites stay resident, so
    /// opening a second beatmap adds to the first rather than replacing it.
    public func unload() {
        audio.unload()
        sprites = []
        spriteCount = 0
        drawnCount = 0
        currentTime = 0
        duration = 1
        timelineRange = 0...1
        isPlaying = false
        hasAudio = false
        audioWarning = nil
        waveform = nil
        timing = nil
        missingImagePaths = []
        isCanvasFullScreen = false
        status = .loading
    }

    public func contentLoaded(
        name: String,
        sprites: [PreparedSprite],
        duration: Double,
        audioURL: URL?,
        timing: BeatmapTimingData? = nil,
        missingImagePaths: Set<String> = [],
    ) {
        self.sprites = sprites
        spriteCount = sprites.count
        let storyboardRange = StoryboardResolver.timeRange(of: sprites)
        self.duration = max(duration, 1)
        timelineRange = storyboardRange
        self.timing = timing
        self.missingImagePaths = missingImagePaths
        status = .ready(name)

        // Paused on arrival: opening a beatmap is a step towards editing it,
        // not a request to play it, and music starting on its own is startling
        // rather than helpful.
        guard let audioURL else {
            hasAudio = false
            return
        }

        do {
            try audio.load(url: audioURL)
            hasAudio = true
            audioWarning = nil
            loadWaveform(from: audioURL)
            // The track defines how long the map is. A storyboard's last
            // command can sit far past the music — a loop left open, or a fade
            // ending at some enormous timestamp — and using that would leave
            // the transport running long after the audio stopped.
            self.duration = audio.duration
            // The ruler spans both, so commands that start before the track or
            // run past its end stay visible and editable.
            timelineRange = min(storyboardRange.lowerBound, 0)...max(
                storyboardRange.upperBound,
                audio.duration,
            )
        } catch {
            hasAudio = false
            audioWarning = String(describing: error)
        }
    }

    /// Reads the track's peaks off the main thread.
    ///
    /// Walking a several-minute file takes long enough to stall a frame, and
    /// the waveform is decoration: playback starts without waiting for it.
    private func loadWaveform(from url: URL) {
        waveform = nil
        // `.userInitiated` rather than `.utility`: the waveform is decoration,
        // but it is decoration someone is waiting to see — at the lowest
        // priority it can sit behind other work long enough to arrive well
        // after the storyboard is already playing.
        Task.detached(priority: .userInitiated) {
            guard let extracted = try? WaveformExtractor.extract(from: url) else { return }
            await MainActor.run { self.waveform = extracted }
        }
    }

    public func contentFailed(_ reason: String) {
        status = .failed(reason)
        isPlaying = false
    }

    // ─── Transport ───────────────────────────────────────────────────────────

    public func togglePlayback() {
        isPlaying ? pause() : startPlayback()
    }

    public func startPlayback() {
        guard !status.isFailure else { return }
        // Restart from the top when resuming at the end.
        if currentTime >= duration - 1 { seek(to: timelineRange.lowerBound) }

        // Not while the clock is still before zero: `advance` starts the track
        // as the playhead reaches it, so the lead-in plays in silence as it
        // should.
        if hasAudio, currentTime >= 0 { audio.play() }
        isPlaying = true
    }

    public func pause() {
        if hasAudio { audio.pause() }
        isPlaying = false
    }

    /// Clamps and applies a seek, in milliseconds.
    ///
    /// The clock follows the timeline, which can open before the track does —
    /// a storyboard is allowed to start early, and scrubbing has to reach the
    /// sprites that live there. The audio is clamped separately, since it has
    /// nothing to play before its own first sample.
    public func seek(to time: Double) {
        currentTime = min(max(timelineRange.lowerBound, time), timelineRange.upperBound)

        if hasAudio {
            audio.seek(toMilliseconds: min(max(0, currentTime), duration))
        }
    }

    public func setVolume(_ volume: Float) {
        audio.volume = volume
    }

    public var volume: Float { audio.volume }

    // ─── Frame updates ───────────────────────────────────────────────────────

    /// Advances the clock by one frame.
    ///
    /// - Parameter delta: elapsed time in milliseconds, used only when there is
    ///   no audio to follow.
    public func advance(by delta: Double) {
        guard isPlaying else { return }

        // Before zero the track has nothing to play, so the clock runs on the
        // frame delta and the audio waits. A storyboard that opens early is
        // meant to be watched through that lead-in rather than skipped past it.
        if currentTime < 0 {
            currentTime = min(currentTime + delta, 0)
            if currentTime >= 0, hasAudio { audio.play() }
            return
        }

        if hasAudio {
            currentTime = min(audio.currentTime, duration)
            if audio.hasReachedEnd { loopToStart() }
        } else {
            currentTime += delta
            if currentTime > duration { loopToStart() }
        }
    }

    private func loopToStart() {
        seek(to: timelineRange.lowerBound)
        if hasAudio, isPlaying, currentTime >= 0 { audio.play() }
    }

    public func frameRendered(drawnCount: Int, framesPerSecond: Double) {
        self.drawnCount = drawnCount
        self.framesPerSecond = framesPerSecond
    }

    // ─── Formatting ──────────────────────────────────────────────────────────

    /// Position formatted as `m:ss.hh`.
    public var timecode: String {
        Self.timecode(for: currentTime)
    }

    public var durationTimecode: String {
        Self.timecode(for: duration)
    }

    private static func timecode(for milliseconds: Double) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let hundredths = Int(milliseconds.truncatingRemainder(dividingBy: 1000) / 10)
        return String(format: "%d:%02d.%02d", totalSeconds / 60, totalSeconds % 60, hundredths)
    }
}
