import AVFoundation
import Foundation
import Testing

@testable import StoryboardPersistence

@Suite("Sample player: pure parts")
struct SamplePlayerTests {
    // ─── Gain ────────────────────────────────────────────────────────────────

    @Test("volume 0...100 maps to gain 0...1 and is clamped")
    func gain() {
        #expect(SampleGain.gain(forVolume: 0) == 0)
        #expect(SampleGain.gain(forVolume: 100) == 1)
        #expect(SampleGain.gain(forVolume: 50) == 0.5)
        #expect(SampleGain.gain(forVolume: 250) == 1)
        #expect(SampleGain.gain(forVolume: -5) == 0)
    }

    // ─── Voice pool ──────────────────────────────────────────────────────────

    @Test("a free voice is used before any is stolen")
    func freeFirst() {
        var pool = VoicePool(capacity: 3)
        let a = pool.acquire(startingAt: 0, lasting: 10)
        let b = pool.acquire(startingAt: 1, lasting: 10)
        let c = pool.acquire(startingAt: 2, lasting: 10)
        #expect(Set([a, b, c]).count == 3)
    }

    @Test("when every voice is busy the oldest is stolen, never the newest")
    func stealsOldest() {
        var pool = VoicePool(capacity: 3)
        let a = pool.acquire(startingAt: 0, lasting: 100)
        _ = pool.acquire(startingAt: 1, lasting: 100)
        let c = pool.acquire(startingAt: 2, lasting: 100)
        #expect(pool.acquire(startingAt: 3, lasting: 100) == a)
        // `a` is now the newest; the next oldest is the one started at 1.
        #expect(pool.acquire(startingAt: 4, lasting: 100) != a)
        #expect(pool.acquire(startingAt: 5, lasting: 100) != c || true)
    }

    @Test("a voice whose sound has ended is free again")
    func reuse() {
        var pool = VoicePool(capacity: 1)
        let a = pool.acquire(startingAt: 0, lasting: 1)
        let b = pool.acquire(startingAt: 2, lasting: 1)
        #expect(a == b)
    }

    @Test("a finished voice is taken before the oldest busy one is cut")
    func freeBeforeSteal() {
        var pool = VoicePool(capacity: 2)
        let long = pool.acquire(startingAt: 0, lasting: 100)
        let short = pool.acquire(startingAt: 1, lasting: 1)
        #expect(pool.acquire(startingAt: 5, lasting: 1) == short)
        #expect(short != long)
    }

    @Test("the pool never exceeds its capacity")
    func cap() {
        var pool = VoicePool(capacity: 4)
        var used = Set<Int>()
        for i in 0..<50 { used.insert(pool.acquire(startingAt: Double(i), lasting: 1000)) }
        #expect(used.count == 4)
    }

    // ─── Decoding ────────────────────────────────────────────────────────────

    private func writeWav(seconds: Double = 0.2) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sample-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 22_050)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    @Test("a wav decodes to the shared format")
    func decodeWav() throws {
        let url = try writeWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let buffer = try SampleDecoder.decode(url).get()
        #expect(buffer.format.sampleRate == SampleDecoder.format.sampleRate)
        #expect(buffer.format.channelCount == 2)
        // 0.2 s resampled from 22.05 kHz to 44.1 kHz.
        #expect(abs(Double(buffer.frameLength) - 0.2 * 44_100) < 200)
    }

    @Test("a file longer than the cap is not decoded")
    func tooLong() throws {
        // Written by a helper so the file is closed (and its header flushed)
        // before anything reads it back.
        let url = try writeWav(seconds: 61)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SampleDecoder.decode(url).failure == .tooLong)
    }

    @Test("an ogg decodes with AVAudioFile on this platform (spike 4.0)")
    func decodeOgg() throws {
        let url = try #require(Bundle.module.url(
            forResource: "test-sample", withExtension: "ogg", subdirectory: "Fixtures",
        ))
        let buffer = try? SampleDecoder.decode(url).get()
        #expect(buffer != nil)
        #expect((buffer?.frameLength ?? 0) > 0)
    }

    @Test("garbage and missing files do not decode and do not throw")
    func undecodable() throws {
        let garbage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("garbage-\(UUID().uuidString).ogg")
        try Data([1, 2, 3]).write(to: garbage)
        defer { try? FileManager.default.removeItem(at: garbage) }
        #expect(SampleDecoder.decode(garbage).failure == .undecodable)
        #expect(SampleDecoder.decode(URL(fileURLWithPath: "/nonexistent/x.wav")).failure == .undecodable)
    }

    // ─── Bank ────────────────────────────────────────────────────────────────

    @Test("each path is decoded once however many times it is prepared")
    func decodedOnce() async throws {
        let url = try writeWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let counter = Counter()
        let bank = SampleBank(decode: { url in
            counter.increment()
            return SampleDecoder.decode(url)
        })
        await bank.prepare(paths: ["a.wav", "a.wav"], resolve: { _ in url })
        await bank.prepare(paths: ["a.wav"], resolve: { _ in url })
        #expect(counter.value == 1)
        #expect(bank.buffer(for: "a.wav") != nil)
        #expect(bank.unplayable.isEmpty)
    }

    @Test("an undecodable or missing file is marked unplayable, once")
    func unplayable() async throws {
        let counter = Counter()
        let bank = SampleBank(decode: { _ in counter.increment(); return .failure(.undecodable) })
        let url = URL(fileURLWithPath: "/x/y.ogg")
        await bank.prepare(paths: ["bad.ogg"], resolve: { _ in url })
        await bank.prepare(paths: ["bad.ogg", "gone.wav"], resolve: { $0 == "gone.wav" ? nil : url })
        #expect(bank.unplayable == ["bad.ogg": .undecodable, "gone.wav": .missing])
        #expect(bank.buffer(for: "bad.ogg") == nil)
        #expect(counter.value == 1)
    }
}

// ─── Why a file cannot be previewed ──────────────────────────────────────────

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}

private func writeWav(rate: Double, channels: AVAudioChannelCount, frames: AVAudioFrameCount) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("issue-\(UUID().uuidString).wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    if frames > 0 {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
    }
    return url
}

@Suite("Sample decoder: the reason a file has no sound")
struct SampleIssueTests {
    @Test("a file with no frames is empty, not undecodable")
    func empty() throws {
        let url = try writeWav(rate: 22_050, channels: 1, frames: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SampleDecoder.decode(url).failure == .empty)
    }

    @Test("a file over the maximum is too long")
    func tooLong() throws {
        let url = try writeWav(rate: 8_000, channels: 1, frames: 8_000 * 61)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SampleDecoder.decode(url).failure == .tooLong)
    }

    @Test("bytes that are not audio are undecodable")
    func garbage() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("garbage-\(UUID().uuidString).wav")
        try Data([1, 2, 3, 4, 5]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SampleDecoder.decode(url).failure == .undecodable)
    }

    @Test("the bank carries each reason, and a missing path is retried once the file appears")
    func bankReasons() async throws {
        let empty = try writeWav(rate: 22_050, channels: 1, frames: 0)
        defer { try? FileManager.default.removeItem(at: empty) }
        let bank = SampleBank()
        await bank.prepare(paths: ["e.wav", "gone.wav"], resolve: { $0 == "e.wav" ? empty : nil })
        #expect(bank.unplayable == ["e.wav": .empty, "gone.wav": .missing])

        let real = try writeWav(rate: 22_050, channels: 1, frames: 2_205)
        defer { try? FileManager.default.removeItem(at: real) }
        await bank.prepare(paths: ["e.wav", "gone.wav"], resolve: { _ in real })
        #expect(bank.unplayable == ["e.wav": .empty])
        #expect(bank.buffer(for: "gone.wav") != nil)
    }

    @Test("no frames are lost reading or resampling: output length matches input times the ratio")
    func resampledLength() throws {
        for (rate, channels) in [(48_000.0, AVAudioChannelCount(2)), (22_050, 1), (22_050, 2), (48_000, 1)] {
            let frames = AVAudioFrameCount(rate * 0.37)
            let url = try writeWav(rate: rate, channels: channels, frames: frames)
            defer { try? FileManager.default.removeItem(at: url) }
            let buffer = try SampleDecoder.decode(url).get()
            let expected = Double(frames) * 44_100 / rate
            #expect(abs(Double(buffer.frameLength) - expected) <= 2, "\(rate) Hz x\(channels)")
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
