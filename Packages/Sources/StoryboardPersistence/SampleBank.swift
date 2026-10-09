import AVFoundation
import Foundation
import StoryboardCore

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

    /// Reads the whole file into `buffer`.
    ///
    /// A single `read(into:)` asked for the file's full length can return
    /// fewer frames — measured: a 48 kHz mono WAV of 17 760 frames came back as
    /// 17 408 — so the tail of the sound was silently clipped before any
    /// conversion happened. Keep reading until the file is exhausted.
    private static func readAll(_ file: AVAudioFile, into buffer: AVAudioPCMBuffer) -> Bool {
        guard let chunk = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: 8192),
              let destination = buffer.floatChannelData
        else { return false }
        buffer.frameLength = 0
        while file.framePosition < file.length {
            guard (try? file.read(into: chunk)) != nil, chunk.frameLength > 0,
                  buffer.frameLength + chunk.frameLength <= buffer.frameCapacity,
                  let source = chunk.floatChannelData
            else { return buffer.frameLength > 0 }
            for channel in 0..<Int(buffer.format.channelCount) {
                (destination[channel] + Int(buffer.frameLength))
                    .update(from: source[channel], count: Int(chunk.frameLength))
            }
            buffer.frameLength += chunk.frameLength
        }
        return true
    }

    /// The decoded sound, or the reason there is none.
    static func decode(_ url: URL) -> Result<AVAudioPCMBuffer, SamplePreviewIssue> {
        guard let file = try? AVAudioFile(forReading: url) else { return .failure(.undecodable) }
        let source = file.processingFormat
        guard file.length > 0 else { return .failure(.empty) }
        guard source.sampleRate > 0 else { return .failure(.undecodable) }
        guard Double(file.length) / source.sampleRate <= maximumSeconds else { return .failure(.tooLong) }
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
              Self.readAll(file, into: input),
              let converter = AVAudioConverter(from: source, to: format)
        else { return .failure(.undecodable) }

        let ratio = format.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return .failure(.undecodable)
        }

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
        guard status != .error, failure == nil, output.frameLength > 0 else { return .failure(.undecodable) }
        return .success(output)
    }
}

/// Decoded samples, keyed by the path the `.osb` names.
///
/// Each path decodes once and off the main thread: a fire only looks the
/// buffer up. A file that cannot be decoded is remembered with its reason
/// rather than retried on every fire, which is also what the editor shows as
/// the "can't preview" badge.
public final class SampleBank: @unchecked Sendable {
    typealias Decode = @Sendable (URL) -> Result<AVAudioPCMBuffer, SamplePreviewIssue>

    private struct Box: @unchecked Sendable { let result: Result<AVAudioPCMBuffer, SamplePreviewIssue> }

    private let lock = NSLock()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var failed: [String: SamplePreviewIssue] = [:]
    private var missing: Set<String> = []
    private let decode: Decode

    init(decode: @escaping Decode = { SampleDecoder.decode($0) }) {
        self.decode = decode
    }

    /// Paths with no sound to play, each with why.
    public var unplayable: [String: SamplePreviewIssue] {
        lock.lock(); defer { lock.unlock() }
        var all = failed
        for path in missing { all[path] = .missing }
        return all
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
                group.addTask { (path, Box(result: decode(url))) }
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
            if buffers[path] != nil || failed[path] != nil { continue }
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
            switch box.result {
            case let .success(buffer): buffers[path] = buffer
            case let .failure(issue): failed[path] = issue
            }
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffers = [:]
        failed = [:]
        missing = []
    }
}
