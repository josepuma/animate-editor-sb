import AVFoundation
import Foundation
import Testing

@testable import StoryboardPersistence

/// A band has to measure its *own* stretch of spectrum.
///
/// **The bug this pins.** The analysis window was a fixed four cycles of each
/// band's centre, which is ample at 24 bands and far too short at 64: a window
/// of N seconds can only separate frequencies 1/N apart, and measured on real
/// music band 30 spanned 59 Hz while four cycles resolved 150, band 60 spanned
/// 1114 against 2837. Neighbouring bands read the same sound, so from band 21
/// up all 43 flattened into half a range — reported as a row of bars that all
/// look the same height.
@Suite("Band resolution")
struct BandResolutionTests {
    /// Two tones a fixed distance apart, so neighbouring bands have something
    /// they can only tell apart with a window long enough to resolve them.
    private func twoTones(_ a: Double, _ b: Double, seconds: Double = 1) throws -> URL {
        let sampleRate = 44_100.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tones-\(UUID().uuidString).wav")
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
        )
        buffer.frameLength = frameCount

        if let channel = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                let t = Double(frame) / sampleRate
                channel[frame] = Float(0.4 * sin(t * a * 2 * .pi) + 0.02 * sin(t * b * 2 * .pi))
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// **Measured through the extractor, never by restating its arithmetic.**
    ///
    /// Two earlier versions of this failed to fail. The first recomputed the
    /// window in the test and agreed with any formula at all; the second
    /// compared a loud tone against a quiet one, which stands out either way.
    /// What actually distinguishes the two is **how sharply the peak falls**:
    /// with a window too short to resolve the bands, a single tone reads almost
    /// as loudly two bands away as it does in its own.
    ///
    /// Measured on one 3 kHz tone across a 64-band bank: the fixed window left
    /// the neighbour at 98% of the peak, the sized one at 77%.
    @Test("a tone falls away from its own band")
    func peakFallsOffSharply() throws {
        let url = try twoTones(3000, 3000)
        defer { try? FileManager.default.removeItem(at: url) }

        let spectrum = try SpectrumExtractor.extract(
            from: url, range: 100...500, bands: 64, interval: 50,
        )
        let frame = try #require(spectrum.frames.dropFirst(1).first)

        let ratio = pow(16_000 / 30.0, 1 / 64.0)
        let index = Int(log(3000 / 30.0) / log(ratio))
        let peak = frame[index]
        let neighbour = max(frame[max(0, index - 2)], frame[min(63, index + 2)])

        #expect(peak > 0.3, "no peak to measure")
        #expect(
            neighbour < peak * 0.9,
            "a band two away reads \(neighbour) against the peak's \(peak) — the bank is smearing",
        )
    }

    /// The band right beside a loud tone must stay quieter than the tone's own,
    /// or the bank is reporting one sound in two places.
    @Test("a loud tone does not fill its neighbouring bands")
    func toneDoesNotLeakSideways() throws {
        let url = try twoTones(3000, 3000)
        defer { try? FileManager.default.removeItem(at: url) }

        let spectrum = try SpectrumExtractor.extract(
            from: url, range: 100...500, bands: 64, interval: 50,
        )
        let frame = try #require(spectrum.frames.dropFirst(1).first)

        let ratio = pow(16_000 / 30.0, 1 / 64.0)
        let index = Int(log(3000 / 30.0) / log(ratio))
        let peak = frame[index]
        let neighbours = [frame[max(0, index - 2)], frame[min(63, index + 2)]]

        for (offset, level) in neighbours.enumerated() {
            #expect(
                level < peak,
                "neighbour \(offset) reads \(level) against the tone's \(peak)",
            )
        }
    }
}
