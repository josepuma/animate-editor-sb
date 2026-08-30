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

    /// Which stage the storyboard is drawn on.
    ///
    /// Taken from the beatmap's own `WidescreenStoryboard` setting, and
    /// overridable: a map can be authored for one and still worth checking
    /// against the other.
    public var isWidescreen = true

    /// What the beatmap itself asks for, so the override can be undone.
    public private(set) var beatmapIsWidescreen = true

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

        // A beatmap with no `.osu` to read is assumed wide, which is what
        // storyboards have been authored for since the setting existed.
        beatmapIsWidescreen = timing?.isWidescreen ?? true
        isWidescreen = beatmapIsWidescreen

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

        // Restart from the top when resuming at the end — the end of the
        // timeline, not of the track: pressing play on a storyboard's closing
        // seconds should play them, not jump back to the beginning.
        if currentTime >= timelineRange.upperBound - 1 {
            seek(to: timelineRange.lowerBound)
        }

        // Only while the playhead is within the track. Outside it, `advance`
        // runs the clock on its own and starts the audio when the playhead
        // arrives, so a lead-in or a tail plays out in silence as it should.
        if hasAudio, currentTime >= 0, currentTime < duration { audio.play() }
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
        guard hasAudio else { return }

        audio.seek(toMilliseconds: min(max(0, currentTime), duration))

        // Landing outside the track silences it: scrubbing into a lead-in or a
        // tail should not leave the first or last moment of the music sounding.
        if isPlaying, currentTime < 0 || currentTime >= duration {
            audio.pause()
        }
    }

    public func setVolume(_ volume: Float) {
        audio.volume = volume
    }

    public var volume: Float { audio.volume }

    /// How far behind the audio engine may report before its position is taken
    /// as a seek rather than as it catching up.
    ///
    /// A few frames' worth: an engine just told to play lags by a frame or two,
    /// while anything further back is somebody having moved the playhead.
    private static let audioCatchUpTolerance: Double = 250

    // ─── Frame updates ───────────────────────────────────────────────────────

    /// Advances the clock by one frame.
    ///
    /// The clock follows the timeline, not the track. A storyboard is allowed
    /// to open before the first note and to run past the last, and both of
    /// those stretches have to play: the audio is one source the clock can
    /// borrow from while it lasts, not the definition of how long the piece is.
    ///
    /// - Parameter delta: elapsed time in milliseconds, used whenever the
    ///   playhead is outside the track and has no audio clock to follow.
    public func advance(by delta: Double) {
        guard isPlaying else { return }

        // Outside the track, the clock runs on the frame delta and the audio
        // stays quiet — a lead-in before the music, or a tail after it.
        guard currentTime >= 0, currentTime < duration, hasAudio, audio.isPlaying else {
            currentTime += delta

            if currentTime > timelineRange.upperBound {
                loopToStart()
            } else if hasAudio, !audio.isPlaying, currentTime >= 0, currentTime < duration {
                // The playhead has reached the track: start it where the clock
                // already is rather than from the top.
                audio.seek(toMilliseconds: currentTime)
                audio.play()
            }
            return
        }

        // Within the track the audio hardware keeps the time, because a display
        // link and an audio device drift apart.
        //
        // Except while the engine is still catching up: told to play, it
        // reports its old position for a few frames, and taking that would snap
        // the playhead back to where the audio was rather than where the clock
        // has reached. A large jump is a seek and is followed; a small step
        // backwards is the engine lagging and is ignored.
        let reported = audio.currentTime
        let isLag = reported < currentTime && currentTime - reported < Self.audioCatchUpTolerance
        currentTime = isLag ? currentTime + delta : reported

        if audio.hasReachedEnd {
            // Past the end of the music the clock carries on by itself, so a
            // storyboard that outlasts its track still plays out.
            audio.pause()
            currentTime = duration

            if currentTime >= timelineRange.upperBound { loopToStart() }
        }
    }

    private func loopToStart() {
        seek(to: timelineRange.lowerBound)
        if hasAudio, isPlaying, currentTime >= 0, currentTime < duration {
            audio.play()
        }
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

    /// How far playback runs, which is the end of the timeline rather than of
    /// the track: the transport counts up to where the storyboard stops.
    public var durationTimecode: String {
        Self.timecode(for: timelineRange.upperBound)
    }

    private static func timecode(for milliseconds: Double) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let hundredths = Int(milliseconds.truncatingRemainder(dividingBy: 1000) / 10)
        return String(format: "%d:%02d.%02d", totalSeconds / 60, totalSeconds % 60, hundredths)
    }
}
