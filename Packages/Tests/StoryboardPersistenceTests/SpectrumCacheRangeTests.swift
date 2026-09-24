import AVFoundation
import Foundation
import Testing

@testable import StoryboardPersistence

/// A range that starts before the song is still the song, in time.
///
/// Reported as "the last seconds of the clip go still, just a line". Audio
/// Waves asks for audio from a little BEFORE its clip, so strands that lag have
/// something to hear from their first frame — and near the start of a song
/// that reaches below zero. The cache cut the song into five-second chunks and
/// asked for chunk −1, which decodes to nothing, yet still counted time from
/// −5s: every sample landed five seconds early. Measured on a real MP3 asked
/// for −180…8000ms, the last two seconds came back at energy 0.0 — and, less
/// visibly and worse, everything before them was out of time with the song.
@Suite("Spectrum cache ranges", .serialized)
struct SpectrumCacheRangeTests {
    /// Four seconds of silence with one loud tone from 1.0s to 1.5s and
    /// another from 3.2s to 3.6s, so where the song is loud is known.
    private func song() throws -> URL {
        let sampleRate = 44_100.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hits-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(4 * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            for frame in 0 ..< Int(frameCount) {
                let t = Double(frame) / sampleRate
                let loud = (1.0 ..< 1.5).contains(t) || (3.2 ..< 3.6).contains(t)
                channel[frame] = loud ? Float(0.6 * sin(t * 220 * 2 * .pi)) : 0
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func energy(_ frames: AudioSpectrumFrames, atSongTime time: Double, from start: Double) -> Float {
        let index = Int((time - start) / 50)
        return frames[min(max(0, index), frames.count - 1)].reduce(0, +)
    }

    private typealias AudioSpectrumFrames = [[Float]]

    @Test("a range reaching before the song keeps the song in time")
    func negativeStartKeepsTime() throws {
        let url = try song()
        defer { try? FileManager.default.removeItem(at: url) }
        SpectrumCache.clear()

        let early = -700.0
        let frames = try #require(SpectrumCache.levels(from: url, range: early ... 3900, bands: 8, interval: 50)).levels

        // Loud where the song is loud, quiet where it is quiet — at song time.
        #expect(energy(frames, atSongTime: 1250, from: early) > 0.1, "the first tone is missing")
        #expect(energy(frames, atSongTime: 2400, from: early) < 0.01, "silence reads loud: the song slid")
        #expect(energy(frames, atSongTime: 3400, from: early) > 0.1, "the last tone went flat")
    }

    /// Before the song starts there is nothing playing, so it reads as quiet
    /// rather than as whatever came first.
    @Test("the time before the song is silence")
    func beforeTheSongIsSilent() throws {
        let url = try song()
        defer { try? FileManager.default.removeItem(at: url) }
        SpectrumCache.clear()

        let frames = try #require(SpectrumCache.levels(from: url, range: -700 ... 3900, bands: 8, interval: 50)).levels
        #expect(energy(frames, atSongTime: -300, from: -700) < 0.01)
    }

    /// The same moment reads the same however early the range begins.
    @Test("the same moment reads the same from any range")
    func sameMomentSameReading() throws {
        let url = try song()
        defer { try? FileManager.default.removeItem(at: url) }
        SpectrumCache.clear()

        let plain = try #require(SpectrumCache.levels(from: url, range: 0 ... 3900, bands: 8, interval: 50)).levels
        let early = try #require(SpectrumCache.levels(from: url, range: -700 ... 3900, bands: 8, interval: 50)).levels
        for time in stride(from: 500.0, through: 3700, by: 400) {
            let a = energy(plain, atSongTime: time, from: 0)
            let b = energy(early, atSongTime: time, from: -700)
            #expect(abs(a - b) < 0.05, "at \(time)ms: \(a) from zero, \(b) from −700")
        }
    }
}
