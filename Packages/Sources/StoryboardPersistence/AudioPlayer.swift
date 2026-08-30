import AVFoundation
import Foundation

/// Plays a beatmap's audio and reports the playback position.
///
/// The position comes from the audio hardware rather than a wall clock: a
/// display link and an audio device drift apart, and a storyboard that follows
/// anything but the audio slides out of sync with the music.
public final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var file: AVAudioFile?

    /// Where in the track the current scheduled segment began.
    private var segmentStartFrame: AVAudioFramePosition = 0

    public private(set) var duration: Double = 0
    public private(set) var isPlaying = false

    public var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = min(max(newValue, 0), 1) }
    }

    public init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    deinit {
        playerNode.stop()
        engine.stop()
    }

    // ─── Loading ─────────────────────────────────────────────────────────────

    /// Loads a track, replacing whatever was playing.
    ///
    /// - Throws: ``AudioPlayerError`` when the file cannot be opened or the
    ///   engine will not start.
    public func load(url: URL) throws {
        stop()

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioPlayerError.couldNotOpen(url.lastPathComponent, String(describing: error))
        }

        guard file.length > 0 else {
            throw AudioPlayerError.emptyFile(url.lastPathComponent)
        }

        self.file = file
        duration = Double(file.length) / file.processingFormat.sampleRate * 1000

        // Reconnect: the mixer needs the new file's sample rate and channel count.
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                throw AudioPlayerError.engineFailed(String(describing: error))
            }
        }
    }

    // ─── Transport ───────────────────────────────────────────────────────────

    /// Starts or resumes playback from the current position.
    public func play() {
        guard file != nil, !isPlaying else { return }
        scheduleSegment(fromFrame: segmentStartFrame)
        playerNode.play()
        isPlaying = true
    }

    public func pause() {
        guard isPlaying else { return }
        // Freeze the position before stopping: the node's own time is reset by
        // `stop()`, so it has to be captured first.
        segmentStartFrame = currentFrame
        playerNode.stop()
        isPlaying = false
    }

    public func stop() {
        playerNode.stop()
        isPlaying = false
        segmentStartFrame = 0
    }

    /// Stops and releases the track.
    ///
    /// `stop` alone leaves the file open and the engine running, which is right
    /// between seeks but wrong when the project closes: the decoder's buffers
    /// stay resident for a track nobody is going to play.
    public func unload() {
        stop()
        engine.stop()
        file = nil
        duration = 0
    }

    /// Seeks to `milliseconds`, resuming if it was already playing.
    public func seek(toMilliseconds milliseconds: Double) {
        guard let file else { return }

        let sampleRate = file.processingFormat.sampleRate
        let clamped = min(max(milliseconds, 0), duration)
        let frame = AVAudioFramePosition(clamped / 1000 * sampleRate)

        let wasPlaying = isPlaying
        playerNode.stop()
        segmentStartFrame = frame

        if wasPlaying {
            scheduleSegment(fromFrame: frame)
            playerNode.play()
        } else {
            isPlaying = false
        }
    }

    // ─── Position ────────────────────────────────────────────────────────────

    /// Current playback position in milliseconds, taken from the audio device.
    public var currentTime: Double {
        guard let file else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        return min(Double(currentFrame) / sampleRate * 1000, duration)
    }

    /// True once playback has run past the end of the track.
    public var hasReachedEnd: Bool {
        guard file != nil, duration > 0 else { return false }
        return currentTime >= duration - 1
    }

    /// Absolute frame position: where the segment started plus what the node
    /// has rendered since.
    private var currentFrame: AVAudioFramePosition {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return segmentStartFrame }

        return segmentStartFrame + playerTime.sampleTime
    }

    // ─── Scheduling ──────────────────────────────────────────────────────────

    /// Queues the rest of the track from `frame`.
    private func scheduleSegment(fromFrame frame: AVAudioFramePosition) {
        guard let file else { return }

        let remaining = file.length - frame
        guard remaining > 0 else { return }

        file.framePosition = frame
        playerNode.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack,
            completionHandler: nil,
        )
    }
}

// ─── Errors ──────────────────────────────────────────────────────────────────

public enum AudioPlayerError: Error, CustomStringConvertible, Equatable {
    case couldNotOpen(String, String)
    case emptyFile(String)
    case engineFailed(String)

    public var description: String {
        switch self {
        case let .couldNotOpen(name, reason):
            "Could not open \(name): \(reason)"
        case let .emptyFile(name):
            "\(name) contains no audio."
        case let .engineFailed(reason):
            "Could not start the audio engine: \(reason)"
        }
    }
}
