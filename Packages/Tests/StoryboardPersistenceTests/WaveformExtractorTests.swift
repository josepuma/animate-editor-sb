import AVFoundation
import Foundation
import Testing

@testable import StoryboardPersistence

/// Writes a throwaway audio file for one test.
private struct TemporaryAudio: ~Copyable {
    let url: URL

    /// - Parameters:
    ///   - seconds: length of the file.
    ///   - amplitude: peak level of the tone, or 0 for silence.
    init(seconds: Double, amplitude: Float = 0.5, sampleRate: Double = 44_100) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("waveform-tests-\(UUID().uuidString).caf")

        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
        )
        buffer.frameLength = frameCount

        // A 440 Hz tone: a predictable shape with a known peak.
        if let channel = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                let phase = Double(frame) / sampleRate * 440 * 2 * .pi
                channel[frame] = amplitude * Float(sin(phase))
            }
        }

        try file.write(from: buffer)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite("WaveformExtractor")
struct WaveformExtractorTests {
    @Test("extracts peaks from a tone")
    func extractsPeaks() throws {
        let audio = try TemporaryAudio(seconds: 1)
        let waveform = try WaveformExtractor.extract(from: audio.url, resolution: 64)

        #expect(!waveform.peaks.isEmpty)
        #expect(waveform.peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("reports the track's length")
    func reportsDuration() throws {
        let audio = try TemporaryAudio(seconds: 2)
        let waveform = try WaveformExtractor.extract(from: audio.url, resolution: 64)

        // Encoders pad slightly, so compare within a frame or two.
        #expect(abs(waveform.duration - 2000) < 50)
    }

    @Test("peaks are normalised so the loudest reaches one")
    func normalisesPeaks() throws {
        // A quiet tone must still fill the waveform's height: the shape is what
        // matters, not the absolute level.
        let audio = try TemporaryAudio(seconds: 1, amplitude: 0.1)
        let waveform = try WaveformExtractor.extract(from: audio.url, resolution: 64)

        let loudest = try #require(waveform.peaks.max())
        #expect(abs(loudest - 1) < 0.01)
    }

    @Test("resolution bounds the number of peaks")
    func resolutionBoundsPeakCount() throws {
        let audio = try TemporaryAudio(seconds: 2)

        let coarse = try WaveformExtractor.extract(from: audio.url, resolution: 32)
        let fine = try WaveformExtractor.extract(from: audio.url, resolution: 256)

        #expect(fine.peaks.count > coarse.peaks.count)
        // Bucketing is integer division, so the count lands near the request
        // rather than exactly on it.
        #expect(coarse.peaks.count <= 40)
    }

    @Test("silence yields peaks at zero")
    func silenceYieldsZeroPeaks() throws {
        let audio = try TemporaryAudio(seconds: 1, amplitude: 0)
        let waveform = try WaveformExtractor.extract(from: audio.url, resolution: 32)

        // Normalising cannot divide by a zero maximum, so the values stay flat.
        #expect(waveform.peaks.allSatisfy { $0 == 0 })
    }

    @Test("a missing file throws")
    func missingFileThrows() {
        let url = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString).wav")

        #expect(throws: WaveformError.self) {
            try WaveformExtractor.extract(from: url)
        }
    }

    @Test("peak lookup covers the whole track")
    func peakLookupSpansTrack() throws {
        let audio = try TemporaryAudio(seconds: 1)
        let waveform = try WaveformExtractor.extract(from: audio.url, resolution: 64)

        // Positions past either end clamp rather than trapping.
        #expect(waveform.peak(at: 0) >= 0)
        #expect(waveform.peak(at: 1) >= 0)
        #expect(waveform.peak(at: -1) >= 0)
        #expect(waveform.peak(at: 2) >= 0)
    }

    @Test("an empty waveform reports no peak")
    func emptyWaveformPeak() {
        #expect(Waveform(peaks: [], duration: 0).peak(at: 0.5) == 0)
    }
}
