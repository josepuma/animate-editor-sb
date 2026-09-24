import Foundation

/// The hits in a song: the moments a band's energy jumps.
///
/// What an effect reacting PER HIT needs, and the reason it can afford to: a
/// ripple on every kick writes commands on every kick, where following the
/// level writes them on every frame. Over a long section that is the
/// difference between a file osu! opens and one it does not.
///
/// **A hit is how FAST the energy rises, not how high it gets.** Detected on
/// spectral flux — the rise from one frame to the next, falls ignored — so a
/// kick's sudden jump registers and a crescendo climbing to the same peak does
/// not. Reading the level itself would call every loud stretch one long hit.
///
/// Pure over a series of numbers, so it is tested against hits placed by hand
/// rather than against the analyser's stand-in, whose smooth sines are exactly
/// the kind of movement this is meant to ignore.
public enum AudioOnsets {
    /// The mean level of some bands, frame by frame.
    public static func energy(of frames: AudioSpectrum.Frames, bands: Range<Int>) -> [Double] {
        frames.levels.map { frame in
            let valid = bands.filter { $0 >= 0 && $0 < frame.count }
            guard !valid.isEmpty else { return 0 }
            return valid.reduce(0.0) { $0 + Double(frame[$1]) } / Double(valid.count)
        }
    }

    /// When the hits land, in ms from the start of the series.
    ///
    /// - Parameters:
    ///   - sensitivity: 0…1, how small a jump still counts. At the top a
    ///     ghost note registers; at the bottom only the big hits do.
    ///   - minimumGap: hits closer than this count once — a flam, or the
    ///     analyser's window catching one kick twice. A pulse that fires twice
    ///     per kick stutters.
    public static func detect(
        _ energy: [Double],
        interval: Double,
        sensitivity: Double = 0.5,
        minimumGap: Double = 120,
    ) -> [Double] {
        guard energy.count >= 3, interval > 0 else { return [] }

        // Stretched to the series' own range, so hits over a loud bed are
        // found like hits over a quiet one — the same reason the audio
        // emitter normalises. A flat series has no range, and no hits.
        guard let low = energy.min(), let high = energy.max(), high - low > 1e-6 else { return [] }
        let level = energy.map { ($0 - low) / (high - low) }

        var flux = [0.0]
        for index in 1 ..< level.count {
            flux.append(max(0, level[index] - level[index - 1]))
        }

        // Two thresholds, and a hit has to clear both. The floor is how small
        // a jump counts at all; the local one stops a dense passage — where
        // everything moves — from firing on every frame, by asking a hit to
        // stand out from its own neighbourhood.
        let floor = 0.5 - 0.45 * min(max(sensitivity, 0), 1)
        let window = 10

        var hits: [Double] = []
        for index in flux.indices {
            let from = max(0, index - window)
            let to = min(flux.count - 1, index + window)
            let local = flux[from ... to].reduce(0, +) / Double(to - from + 1)
            let threshold = max(floor, local * 2)

            guard flux[index] > threshold else { continue }
            // The top of the rise, not somewhere on its way up.
            if index > 0, flux[index] < flux[index - 1] { continue }
            if index + 1 < flux.count, flux[index] <= flux[index + 1] { continue }

            let time = Double(index) * interval
            if let last = hits.last, time - last < minimumGap { continue }
            hits.append(time)
        }
        return hits
    }
}
