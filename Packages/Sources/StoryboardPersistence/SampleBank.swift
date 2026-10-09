import AVFoundation
import Foundation

/// Turns a sample file into the one format every voice plays.
///
/// Converting once, up front, is what lets a pool of identical nodes serve any
/// file: the mixer connection has a single format, and a fire is only a
/// `scheduleBuffer`.
enum SampleDecoder {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    /// A sound effect is short. Anything longer is a song pasted in by
    /// mistake, and holding minutes of decoded audio per path is memory spent
    /// on a mistake.
    static let maximumSeconds: Double = 60

    /// `nil` for a file this platform cannot open or that holds no audio.
    static func decode(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let source = file.processingFormat
        guard file.length > 0, source.sampleRate > 0,
              Double(file.length) / source.sampleRate <= maximumSeconds,
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil,
              let converter = AVAudioConverter(from: source, to: format)
        else { return nil }

        let ratio = format.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        nonisolated(unsafe) var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, failure == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

/// Decoded samples, keyed by the path the `.osb` names.
///
/// Each path decodes once and off the main thread: a fire only looks the
/// buffer up. A file that cannot be decoded is remembered as unplayable rather
/// than retried on every fire, which is also what the editor shows as the
/// "can't preview" badge.
public final class SampleBank: @unchecked Sendable {
    typealias Decode = @Sendable (URL) -> AVAudioPCMBuffer?

    private struct Box: @unchecked Sendable { let buffer: AVAudioPCMBuffer? }

    private let lock = NSLock()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var failed: Set<String> = []
    private var missing: Set<String> = []
    private let decode: Decode

    init(decode: @escaping Decode = { SampleDecoder.decode($0) }) {
        self.decode = decode
    }

    /// Paths with no sound to play: not found, or not decodable here.
    public var unplayable: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return failed.union(missing)
    }

    func buffer(for path: String) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffers[path]
    }

    /// Decodes whatever of `paths` is not already known.
    ///
    /// A path that cannot be found is looked up again next time — the file may
    /// have been imported since — while a decode that failed stays failed.
    func prepare(paths: [String], resolve: @Sendable (String) -> URL?) async {
        let wanted = plan(paths, resolve: resolve)

        let decode = self.decode
        let results = await withTaskGroup(of: (String, Box).self) { group in
            for (path, url) in wanted {
                group.addTask { (path, Box(buffer: decode(url))) }
            }
            var collected: [(String, Box)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        record(results)
    }

    // Synchronous on purpose: an `NSLock` cannot be held in an async body.
    private func plan(_ paths: [String], resolve: @Sendable (String) -> URL?) -> [(String, URL)] {
        lock.lock(); defer { lock.unlock() }
        var wanted: [(String, URL)] = []
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            if buffers[path] != nil || failed.contains(path) { continue }
            if let url = resolve(path) {
                missing.remove(path)
                wanted.append((path, url))
            } else {
                missing.insert(path)
            }
        }
        return wanted
    }

    private func record(_ results: [(String, Box)]) {
        lock.lock(); defer { lock.unlock() }
        for (path, box) in results {
            if let buffer = box.buffer { buffers[path] = buffer } else { failed.insert(path) }
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffers = [:]
        failed = []
        missing = []
    }
}
