import Accelerate
import AVFoundation
import Foundation

/// Energy per frequency band, sampled across a stretch of a track.
///
/// What a spectrum analyser draws: bass on the left, treble on the right, each
/// column rising and falling with the music. The waveform already in the
/// timeline is one magnitude per bucket — enough to draw a shape, and not
/// enough to tell a kick from a hi-hat.
public struct Spectrum: Sendable {
    /// Levels in 0...1, indexed `[frame][band]`.
    public let frames: [[Float]]
    /// How far apart the frames are, in milliseconds.
    public let interval: Double
    /// Where in the track the first frame sits, in milliseconds.
    public let start: Double

    public init(frames: [[Float]], interval: Double, start: Double) {
        self.frames = frames
        self.interval = interval
        self.start = start
    }

    public var bandCount: Int { frames.first?.count ?? 0 }

    /// The levels at a moment in the track.
    ///
    /// Held rather than interpolated between frames: a bar that eases from one
    /// reading to the next is what the effect writes as commands, and averaging
    /// here would smear the attack that makes a spectrum read as music.
    public func levels(atTrackTime time: Double) -> [Float] {
        guard !frames.isEmpty, interval > 0 else { return [] }
        let index = Int((time - start) / interval)
        return frames[min(max(0, index), frames.count - 1)]
    }
}

/// Reads a stretch of audio and reduces it to energy per frequency band.
///
/// **A filter bank rather than an FFT.** A spectrum analyser needs a couple of
/// dozen bands, and a bank of band-pass filters gives exactly that for a
/// fraction of the work — an FFT computes hundreds of bins that then have to be
/// grouped back down. The bands are spaced logarithmically, because pitch is:
/// linear bands put almost everything in the first column and leave the rest
/// nearly empty.
public enum SpectrumExtractor {
    /// The range worth showing.
    ///
    /// Below 30Hz is rumble no speaker reproduces; above 16kHz is beyond most
    /// listeners and beyond most encodes. Bands outside it are columns that
    /// never move.
    private static let lowestFrequency: Double = 30
    private static let highestFrequency: Double = 16_000

    /// Extracts a spectrum from part of a track.
    ///
    /// - Parameters:
    ///   - range: the stretch of the track to analyse, in milliseconds.
    ///   - bands: how many frequency columns to produce.
    ///   - interval: milliseconds between frames.
    public static func extract(
        from url: URL,
        range: ClosedRange<Double>,
        bands: Int,
        interval: Double,
    ) throws -> Spectrum {
        guard bands > 0, interval > 0 else { throw WaveformError.emptyFile(url.lastPathComponent) }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw WaveformError.couldNotOpen(url.lastPathComponent, String(describing: error))
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard file.length > 0 else { throw WaveformError.emptyFile(url.lastPathComponent) }

        // The window each frame measures.
        //
        // Wider than the interval on purpose: a window shorter than a bass
        // period cannot see bass at all — 30Hz needs 33ms just for one cycle.
        // Overlapping windows also smooth the reading, which is what stops a
        // spectrum flickering between frames.
        let windowSeconds = max(interval / 1000 * 2, 0.046)
        let windowFrames = Int(windowSeconds * sampleRate)

        let edges = bandEdges(count: bands, sampleRate: sampleRate)

        var extracted: [[Float]] = []
        let frameCount = max(1, Int((range.upperBound - range.lowerBound) / interval))
        extracted.reserveCapacity(frameCount)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(windowFrames),
        ) else { throw WaveformError.allocationFailed }

        var samples = [Float](repeating: 0, count: windowFrames)

        for index in 0 ..< frameCount {
            let at = range.lowerBound + Double(index) * interval
            let position = AVAudioFramePosition(at / 1000 * sampleRate)
            guard position >= 0, position < file.length else {
                extracted.append([Float](repeating: 0, count: bands))
                continue
            }

            file.framePosition = position
            let wanted = AVAudioFrameCount(min(windowFrames, Int(file.length - position)))
            guard wanted > 0, (try? file.read(into: buffer, frameCount: wanted)) != nil,
                  buffer.frameLength > 0, let channels = buffer.floatChannelData
            else {
                extracted.append([Float](repeating: 0, count: bands))
                continue
            }

            // Mixed to mono: a spectrum is about what is playing, not about
            // where it sits in the stereo field.
            let length = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            for frame in 0 ..< length {
                var sum: Float = 0
                for channel in 0 ..< channelCount { sum += channels[channel][frame] }
                samples[frame] = sum / Float(channelCount)
            }
            if length < windowFrames {
                for frame in length ..< windowFrames { samples[frame] = 0 }
            }

            extracted.append(levels(of: samples, edges: edges, sampleRate: sampleRate))
        }

        return Spectrum(frames: extracted, interval: interval, start: range.lowerBound)
    }

    /// Band boundaries, spaced by pitch rather than by frequency.
    ///
    /// An octave is a doubling, so equal *ratios* are what read as equal steps.
    /// Spaced linearly, the first band would hold every drum and bass note in
    /// the mix while the last ones sat empty.
    private static func bandEdges(count: Int, sampleRate: Double) -> [(low: Double, high: Double)] {
        let top = min(highestFrequency, sampleRate / 2 * 0.95)
        let ratio = pow(top / lowestFrequency, 1 / Double(count))

        return (0 ..< count).map { index in
            (
                low: lowestFrequency * pow(ratio, Double(index)),
                high: lowestFrequency * pow(ratio, Double(index + 1))
            )
        }
    }

    /// One frame's worth of levels.
    ///
    /// A Goertzel-style band pass per band: cheap, and exact enough for
    /// something that drives a bar's height.
    private static func levels(
        of samples: [Float],
        edges: [(low: Double, high: Double)],
        sampleRate: Double,
    ) -> [Float] {
        edges.map { edge in
            // The band's centre, measured by pitch rather than by arithmetic:
            // the midpoint of 100Hz and 200Hz is an octave's middle at 141Hz,
            // not at 150.
            let centre = (edge.low * edge.high).squareRoot()
            let energy = goertzel(samples, frequency: centre, sampleRate: sampleRate)

            // Compressed, because loudness is logarithmic and a linear scale
            // leaves every bar but the loudest flat on the floor — the same
            // reason the waveform takes a square root.
            let decibels = 20 * log10(max(energy, 1e-6))
            let normalised = (decibels + 60) / 60
            return Float(min(max(normalised, 0), 1))
        }
    }

    /// How much of one frequency is present in a window.
    ///
    /// The Goertzel algorithm: a single-bin DFT, which is exactly what a band
    /// needs and a fraction of the cost of transforming the whole window when
    /// only a couple of dozen bins are wanted.
    private static func goertzel(
        _ samples: [Float],
        frequency: Double,
        sampleRate: Double,
    ) -> Double {
        guard !samples.isEmpty else { return 0 }

        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)

        var s1 = 0.0
        var s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }

        let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
        return (power.squareRoot() * 2) / Double(samples.count)
    }
}
