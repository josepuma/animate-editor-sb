import AVFoundation
import Foundation

/// Peak amplitudes sampled across a track, for drawing a waveform.
public struct Waveform: Sendable {
    /// Peak level per bucket, each in 0...1.
    public let peaks: [Float]
    /// Length of the track in milliseconds.
    public let duration: Double

    public init(peaks: [Float], duration: Double) {
        self.peaks = peaks
        self.duration = duration
    }

    /// Peak at a normalised position along the track.
    public func peak(at position: Double) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let index = Int(position * Double(peaks.count - 1))
        return peaks[min(max(0, index), peaks.count - 1)]
    }
}

/// Reads an audio file and reduces it to a fixed number of peaks.
///
/// A waveform only needs one value per column of pixels, so the file is walked
/// once and reduced as it goes: holding a decoded track in memory to draw a few
/// hundred bars would cost tens of megabytes for no benefit.
public enum WaveformExtractor {
    /// Number of buckets to reduce the track into.
    ///
    /// Roughly two per point across a wide window, so the shape stays smooth
    /// when the timeline is zoomed out and the cost stays fixed regardless of
    /// how long the track is.
    public static let defaultResolution = 2048

    /// Extracts peaks from `url`.
    ///
    /// - Throws: ``WaveformError`` when the file cannot be read.
    public static func extract(
        from url: URL,
        resolution: Int = defaultResolution,
    ) throws -> Waveform {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw WaveformError.couldNotOpen(url.lastPathComponent, String(describing: error))
        }

        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0, resolution > 0 else {
            throw WaveformError.emptyFile(url.lastPathComponent)
        }

        let duration = Double(totalFrames) / format.sampleRate * 1000
        let framesPerBucket = max(1, Int(totalFrames) / resolution)

        var peaks: [Float] = []
        peaks.reserveCapacity(resolution)

        // Read in chunks rather than all at once: a long track decoded whole
        // would occupy far more memory than the few hundred values wanted.
        let chunkFrames = AVAudioFrameCount(min(framesPerBucket * 32, 1 << 20))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw WaveformError.allocationFailed
        }

        var bucketEnergy: Double = 0
        var framesInBucket = 0

        while file.framePosition < totalFrames {
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                break
            }
            guard buffer.frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else { break }

            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)

            for frame in 0..<frameCount {
                // Mix channels down to one magnitude: a stereo waveform drawn
                // as a single trace is what the eye reads as "the music".
                var magnitude: Float = 0
                for channel in 0..<channelCount {
                    magnitude = max(magnitude, abs(channels[channel][frame]))
                }

                // Sum of squares, for an RMS average rather than a peak. Peak
                // flattens a track with steady percussion: nearly every bucket
                // contains one loud transient, so every bar reaches the top and
                // the waveform reads as a fence.
                bucketEnergy += Double(magnitude * magnitude)
                framesInBucket += 1

                if framesInBucket >= framesPerBucket {
                    peaks.append(Float((bucketEnergy / Double(framesInBucket)).squareRoot()))
                    bucketEnergy = 0
                    framesInBucket = 0
                }
            }
        }

        if framesInBucket > 0 {
            peaks.append(Float((bucketEnergy / Double(framesInBucket)).squareRoot()))
        }
        guard !peaks.isEmpty else { throw WaveformError.emptyFile(url.lastPathComponent) }

        return Waveform(peaks: normalised(peaks), duration: duration)
    }

    /// Scales peaks so the loudest reaches 1, then lifts the quiet end.
    ///
    /// RMS values cluster low — a track mixed at a steady level rarely averages
    /// above a third of full scale — so a linear mapping leaves most bars near
    /// the floor. The square root spreads that cluster across the height, which
    /// is the same reason level meters are drawn on a curve.
    private static func normalised(_ peaks: [Float]) -> [Float] {
        guard let loudest = peaks.max(), loudest > 0 else { return peaks }
        return peaks.map { ($0 / loudest).squareRoot() }
    }
}

// ─── Errors ──────────────────────────────────────────────────────────────────

public enum WaveformError: Error, CustomStringConvertible, Equatable {
    case couldNotOpen(String, String)
    case emptyFile(String)
    case allocationFailed

    public var description: String {
        switch self {
        case let .couldNotOpen(name, reason):
            "Could not read \(name): \(reason)"
        case let .emptyFile(name):
            "\(name) contains no audio."
        case .allocationFailed:
            "Could not allocate an audio buffer."
        }
    }
}
