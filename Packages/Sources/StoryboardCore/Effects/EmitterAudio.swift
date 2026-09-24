import Foundation

public extension EmitterEffect {
    /// Which part of the song an audio emitter listens to.
    ///
    /// Four named ranges rather than a pair of band numbers: "the kick" and
    /// "the hi-hats" are what somebody means, and band 6 of 32 is not a thing
    /// anyone hears. Split over the analyser's 32 log-spaced bands, which is
    /// why bass gets so few of them: an octave is a doubling, and the bottom
    /// of the spectrum is a handful of octaves packed into the first bands.
    enum AudioBand: String, CaseIterable, Sendable {
        case all = "All"
        case bass = "Bass"
        case mids = "Mids"
        case highs = "Highs"

        /// The analyser bands this listens to.
        public var bands: Range<Int> {
            switch self {
            case .all: 0 ..< EmitterAudio.bands
            case .bass: 0 ..< 6
            case .mids: 6 ..< 18
            case .highs: 18 ..< EmitterAudio.bands
            }
        }
    }
}

/// The song under an audio emitter, read once per evaluation.
///
/// **The count stays a total.** Following the music moves *when* particles are
/// born, never how many: every one is still a sprite whose whole life is baked
/// into the file, so the ceiling and the cost of the `.osb` are exactly what
/// they were. A loud stretch gets more of the budget and a quiet one less.
///
/// **Read under the clip, in SONG time.** This is the one rule it breaks:
/// every other emitter draws the same particles wherever its clip is dragged,
/// and this one hears whatever is playing underneath — so moving it changes
/// the pattern. Audio Bars works the same way, and it is what reacting to the
/// song means. With no analyser the stand-in wave is relative to the clip, so
/// in a project without a song it does stay put.
struct EmitterAudio {
    /// 32 bands every 50ms: the same frames a script's `audio` asks for, so
    /// the analysis chunks one clip reads are the ones the next one finds
    /// cached.
    static let bands = 32
    static let interval: Double = 50

    /// A floor under every weight, so silence still gets a trickle and the
    /// cumulative curve never flattens into one a birth cannot be found on.
    private static let floor = 0.01

    /// Level per frame, per column. One column unless the shape is a spectrum.
    private let levels: [[Double]]
    private let weights: [[Double]]
    private let duration: Double

    var columns: Int { levels.first?.count ?? 1 }

    /// - Parameters:
    ///   - columns: how many columns a spectrum splits the bands into, or 0
    ///     to read `band` as a single level.
    ///   - contrast: an exponent on each level before it becomes a weight.
    ///     At 1 births follow loudness plainly; higher, a hit takes a far
    ///     bigger share than a hum, which is what makes it read as a hit.
    init(
        start: Double,
        duration: Double,
        band: EmitterEffect.AudioBand,
        columns: Int,
        contrast: Double,
        analyser: AudioSpectrum.Analyser?,
    ) {
        self.duration = duration
        let frames = AudioSpectrum.levels(
            in: start ... (start + duration),
            bands: Self.bands,
            interval: Self.interval,
            using: analyser,
        ).levels

        let groups: [Range<Int>] = if columns > 0 {
            // Each column averages its share of the bands, bass on the left.
            (0 ..< columns).map { column in
                let from = column * Self.bands / columns
                let to = max(from + 1, (column + 1) * Self.bands / columns)
                return from ..< min(to, Self.bands)
            }
        } else {
            [band.bands]
        }

        let exponent = max(0.1, contrast)
        let raw = frames.map { frame in
            groups.map { range in
                let valid = range.filter { $0 < frame.count }
                guard !valid.isEmpty else { return 0.0 }
                return valid.reduce(0.0) { $0 + Double(frame[$1]) } / Double(valid.count)
            }
        }

        // Stretched to this clip's own range, so what the emitter follows is
        // the music's dynamics HERE rather than how loud it is overall. A
        // chorus that is loud from end to end barely moves in absolute terms —
        // measured on the stand-in, averaging every band swung only 0.40 to
        // 0.60 — and followed as-is, its births came out nearly even: the hits
        // were there and the emitter could not hear them over the wall.
        //
        // Across the whole grid, not per column: stretching each band on its
        // own would make quiet treble as loud as the bass beside it.
        let flat = raw.flatMap { $0 }
        let low = flat.min() ?? 0
        let span = (flat.max() ?? 0) - low
        levels = span > 1e-6
            ? raw.map { row in row.map { ($0 - low) / span } }
            : raw
        weights = levels.map { row in row.map { pow(max(0, $0), exponent) + Self.floor } }
    }

    private func frame(at time: Double) -> Int {
        min(max(0, levels.count - 1), max(0, Int(time / Self.interval)))
    }

    /// How loud it was at `time`, 0…1, in one column or the only one.
    func level(at time: Double, column: Int = 0) -> Double {
        guard !levels.isEmpty else { return 0 }
        let row = levels[frame(at: time)]
        return row[min(max(0, column), row.count - 1)]
    }

    /// When each of `count` particles is born, and from which column.
    ///
    /// An inverse of the cumulative weight, walked by index rather than
    /// sampled — the same reason a continuous emitter spreads by index: a
    /// random release clumps, and here the clumps would be noise laid over
    /// the music. The walk runs frame by frame and column by column inside
    /// each frame, so a spectrum's loud bands take their share at the moment
    /// they are loud.
    func births(count: Int) -> [(time: Double, column: Int)] {
        let columns = self.columns
        let total = weights.reduce(0.0) { $0 + $1.reduce(0, +) }
        guard count > 0, total > 0 else {
            return (0 ..< max(0, count)).map { index in
                (duration * Double(index) / Double(max(1, count)), 0)
            }
        }

        var result: [(time: Double, column: Int)] = []
        result.reserveCapacity(count)
        var cell = 0
        var before = 0.0
        let cells = weights.count * columns

        for index in 0 ..< count {
            let target = (Double(index) + 0.5) / Double(count) * total
            while cell < cells - 1,
                  before + weights[cell / columns][cell % columns] < target {
                before += weights[cell / columns][cell % columns]
                cell += 1
            }
            let weight = weights[cell / columns][cell % columns]
            let within = min(1, max(0, (target - before) / weight))
            let time = (Double(cell / columns) + within) * Self.interval
            result.append((min(time, max(0, duration - 1)), cell % columns))
        }
        return result
    }

    /// A column for a particle born at `time` by some other emission mode,
    /// weighted by how loud each column is right then.
    func column(at time: Double, draw: Double) -> Int {
        guard !weights.isEmpty else { return 0 }
        let row = weights[frame(at: time)]
        let target = draw * row.reduce(0, +)
        var running = 0.0
        for (index, weight) in row.enumerated() {
            running += weight
            if target < running { return index }
        }
        return row.count - 1
    }
}
