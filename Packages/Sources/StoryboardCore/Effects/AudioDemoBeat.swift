import Foundation

public extension AudioSpectrum {
    /// A four-on-the-floor loop at 120 BPM, for pictures made with no song.
    ///
    /// The library's previews have no track to read, and the stand-in wave is
    /// smooth sines — which is right for bars that only need to move, and
    /// useless for anything fired by a hit: a kick-triggered preset would sit
    /// still in its own preview and read as broken. So the previews play this.
    ///
    /// Kick on every beat in the bass, snare on two and four in the mids,
    /// hats on every eighth in the highs — each a sharp attack and a quick
    /// decay, the shape the onset detector is built to find. Deterministic,
    /// and measured in song time, so the same preview draws the same frames.
    ///
    /// Never used for a real project: there the song is the song, and a clip
    /// that heard this would be dancing to something nobody else can hear.
    static let demoBeat: Analyser = { range, bands, interval in
        let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
        let beat = 500.0

        /// A hit's energy `since` ms after it lands.
        func hit(_ since: Double, peak: Double, fall: Double) -> Double {
            since >= 0 ? peak * pow(fall, since / interval) : 0
        }

        let levels = (0 ..< count).map { frame -> [Float] in
            let time = range.lowerBound + Double(frame) * interval
            let inBeat = time.truncatingRemainder(dividingBy: beat)
            let inBar = time.truncatingRemainder(dividingBy: beat * 2)
            let kick = max(0.08, hit(inBeat, peak: 0.95, fall: 0.5))
            let snare = max(0.1, inBar >= beat ? hit(inBar - beat, peak: 0.8, fall: 0.55) : 0)
            let hat = max(0.06, hit(time.truncatingRemainder(dividingBy: beat / 2), peak: 0.6, fall: 0.4))

            return (0 ..< bands).map { band in
                let position = Double(band) / Double(max(1, bands - 1))
                let level: Double = if position < 6.0 / 32 {
                    kick
                } else if position < 18.0 / 32 {
                    snare
                } else {
                    hat
                }
                return Float(min(1, level))
            }
        }
        return Frames(levels: levels, interval: interval)
    }
}
