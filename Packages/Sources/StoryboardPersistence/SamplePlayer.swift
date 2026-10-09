import AVFoundation
import Foundation
import StoryboardCore

/// Plays a storyboard's sound samples in the preview.
///
/// A pool of player nodes on the music's own engine, wired to the main mixer
/// *beside* the time-pitch unit rather than through it: a sample's start is
/// scheduled against the host clock, and behind a time-pitch that time gets
/// stretched, so a clap would land off the beat. Sample start instants follow
/// the playback rate (`SampleSchedule` divides by it); the sound itself is not
/// stretched, and a clap at half speed is still a clap.
public final class SamplePlayer: @unchecked Sendable {
    /// Voices that can sound at once. A drum roll over a long sample is the
    /// realistic worst case; past this the oldest voice is cut.
    public static let polyphony = 16

    private let engine: AVAudioEngine
    private let nodes: [AVAudioPlayerNode]
    private let bank = SampleBank()
    private let lock = NSLock()
    private var pool = VoicePool(capacity: SamplePlayer.polyphony)

    init(engine: AVAudioEngine) {
        self.engine = engine
        nodes = (0..<Self.polyphony).map { _ in AVAudioPlayerNode() }
        for node in nodes {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: SampleDecoder.format)
        }
    }

    /// Paths that cannot be previewed. The export still copies them.
    public var unplayable: [String: SamplePreviewIssue] { bank.unplayable }

    /// Decodes the samples' files, off the calling thread.
    public func load(_ samples: [StoryboardSample], resolve: @Sendable (String) -> URL?) async {
        await bank.prepare(paths: samples.map(\.path), resolve: resolve)
    }

    /// Starts `path` after `delay` wall-clock milliseconds. A file with no
    /// decoded sound is a silent no-op: the badge already says so.
    public func play(path: String, volume: Int, after delay: Double) {
        guard let buffer = bank.buffer(for: path) else { return }
        if !engine.isRunning, (try? engine.start()) == nil { return }

        let delaySeconds = max(0, delay) / 1000
        let length = Double(buffer.frameLength) / SampleDecoder.format.sampleRate
        lock.lock()
        let index = pool.acquire(
            startingAt: ProcessInfo.processInfo.systemUptime + delaySeconds, lasting: length,
        )
        lock.unlock()

        let node = nodes[index]
        // Stopping first drops whatever the stolen voice still had queued.
        node.stop()
        node.volume = SampleGain.gain(forVolume: volume)
        let when: AVAudioTime? = delaySeconds > 0
            ? AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delaySeconds))
            : nil
        node.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
        node.play()
    }

    /// Cuts every voice: pause, seek, loop and unload.
    public func stopAll() {
        for node in nodes { node.stop() }
        lock.lock()
        pool.reset()
        lock.unlock()
    }

    /// Forgets every decoded file, for the next project.
    public func unload() {
        stopAll()
        bank.clear()
    }
}
