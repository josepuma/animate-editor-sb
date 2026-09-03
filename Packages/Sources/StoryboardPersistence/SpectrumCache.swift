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
    /// One analysed minute, keyed by everything that changes its contents.
    private struct Key: Hashable {
        let path: String
        let minute: Int
        let bands: Int
        let interval: Double
    }

    /// How much audio one entry covers.
    ///
    /// Five seconds, not a minute. The first ask has to analyse whatever it
    /// lands in, and a minute took **8.2 seconds** to animate an eight-second
    /// clip — the cure worse than the disease. Short chunks make the first ask
    /// proportional to the clip while still letting an edit reuse everything
    /// but the piece it grew into.
    private static let chunk: Double = 5000

    nonisolated(unsafe) private static var cache: [Key: [[Float]]] = [:]
    private static let lock = NSLock()

    /// The levels over a range, analysing only the minutes not already held.
    public static func levels(
        from url: URL,
        range: ClosedRange<Double>,
        bands: Int,
        interval: Double,
    ) -> AudioSpectrum.Frames? {
        guard interval > 0, bands > 0, range.upperBound > range.lowerBound else { return nil }

        let first = Int(floor(range.lowerBound / chunk))
        let last = Int(floor(range.upperBound / chunk))

        var assembled: [[Float]] = []

        for minute in first ... last {
            let key = Key(path: url.path, minute: minute, bands: bands, interval: interval)

            lock.lock()
            let held = cache[key]
            lock.unlock()

            let frames: [[Float]]
            if let held {
                frames = held
            } else {
                let start = Double(minute) * chunk
                guard let spectrum = try? SpectrumExtractor.extract(
                    from: url,
                    range: start ... (start + chunk),
                    bands: bands,
                    interval: interval,
                ) else { return nil }

                frames = spectrum.frames
                lock.lock()
                cache[key] = frames
                lock.unlock()
            }

            assembled += frames
        }

        // Trim to what was actually asked for. The chunks start on a minute
        // boundary, so the offset is how far into the first one the range
        // begins.
        let offset = Int((range.lowerBound - Double(first) * chunk) / interval)
        let wanted = Int((range.upperBound - range.lowerBound) / interval)
        guard offset >= 0, offset < assembled.count else { return nil }

        let end = min(offset + wanted, assembled.count)
        return AudioSpectrum.Frames(
            levels: Array(assembled[offset ..< end]),
            interval: interval,
        )
    }

    /// Drops everything held, for when the project changes.
    public static func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
