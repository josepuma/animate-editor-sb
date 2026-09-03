import Foundation
import StoryboardCore

/// Keeps analysed audio so a clip is not re-read on every edit.
///
/// Reading a stretch of a compressed file is expensive and the cost is almost
/// all in getting there: a seek into an MP3 makes the decoder work forward from
/// the start, measured at over a second. That is fine once and ruinous on every
/// keystroke — and dragging a clip's edge asks for a slightly different range
/// each time, so nothing was ever reused.
///
/// Whole minutes are cached rather than the exact range asked for, so a clip
/// stretched by a second answers from what is already in hand.
public enum SpectrumCache {
    /// One decoded chunk, keyed by **what it contains** — not by what anyone
    /// asked of it.
    ///
    /// The band count and the interval used to be part of this, so changing the
    /// number of bars threw away the decoded audio along with the analysis and
    /// re-read the file. Those two change what is *computed from* the samples,
    /// never the samples: decoding is nearly all of the cost, and it had been
    /// tied to the cheapest thing to vary.
    private struct Key: Hashable {
        let path: String
        let minute: Int
    }

    /// How much audio one entry covers.
    ///
    /// Five seconds, not a minute. The first ask has to analyse whatever it
    /// lands in, and a minute took **8.2 seconds** to animate an eight-second
    /// clip — the cure worse than the disease. Short chunks make the first ask
    /// proportional to the clip while still letting an edit reuse everything
    /// but the piece it grew into.
    private static let chunk: Double = 5000

    nonisolated(unsafe) private static var cache: [Key: DecodedAudio] = [:]

    /// Finished analyses, by exactly what was asked for.
    ///
    /// The samples cache spares the file read; this spares the filter bank,
    /// which turned out to be the expensive half — measured, a spectrum over
    /// eight seconds is 137ms of decoding and 393ms of Goertzel. Without it,
    /// **moving any clip** re-ran that bank for every Audio Bars in the
    /// project, because the evaluator rebuilds the whole document on any edit.
    private struct AnalysisKey: Hashable {
        let path: String
        let start: Double
        let end: Double
        let bands: Int
        let interval: Double
    }

    nonisolated(unsafe) private static var analyses: [AnalysisKey: AudioSpectrum.Frames] = [:]
    private static let lock = NSLock()

    /// The levels over a range, decoding only the chunks not already held.
    public static func levels(
        from url: URL,
        range: ClosedRange<Double>,
        bands: Int,
        interval: Double,
    ) -> AudioSpectrum.Frames? {
        guard interval > 0, bands > 0, range.upperBound > range.lowerBound else { return nil }

        let analysisKey = AnalysisKey(
            path: url.path,
            start: range.lowerBound,
            end: range.upperBound,
            bands: bands,
            interval: interval,
        )
        lock.lock()
        let finished = analyses[analysisKey]
        lock.unlock()
        if let finished { return finished }

        let first = Int(floor(range.lowerBound / chunk))
        let last = Int(floor(range.upperBound / chunk))

        // The decoded audio for every chunk the range touches, read once and
        // kept. Changing the band count re-runs the filter bank below and
        // touches none of this.
        var samples: [Float] = []
        var sampleRate: Double = 0

        for minute in first ... last {
            let key = Key(path: url.path, minute: minute)

            lock.lock()
            let held = cache[key]
            lock.unlock()

            let audio: DecodedAudio
            if let held {
                audio = held
            } else {
                let start = Double(minute) * chunk
                guard let decoded = try? SpectrumExtractor.decode(
                    from: url,
                    range: start ... (start + chunk),
                    // No padding on a cached chunk: the next one starts exactly
                    // where this ends, so a window running past the edge finds
                    // its audio there.
                    padding: 0,
                ) else { return nil }

                audio = decoded
                lock.lock()
                cache[key] = decoded
                lock.unlock()
            }

            if sampleRate == 0 { sampleRate = audio.sampleRate }
            samples += audio.samples
        }

        guard sampleRate > 0 else { return nil }

        // Analysed against the whole stretch, with its own start, so a window
        // is cut from the right place however many chunks it spans.
        let stitched = DecodedAudio(
            samples: samples,
            sampleRate: sampleRate,
            start: Double(first) * chunk,
        )
        let spectrum = SpectrumExtractor.analyse(
            stitched, range: range, bands: bands, interval: interval,
        )
        let frames = AudioSpectrum.Frames(levels: spectrum.frames, interval: spectrum.interval)

        lock.lock()
        analyses[analysisKey] = frames
        lock.unlock()

        return frames
    }

    /// Drops everything held, for when the project changes.
    public static func clear() {
        lock.lock()
        cache.removeAll()
        analyses.removeAll()
        lock.unlock()
    }
}
