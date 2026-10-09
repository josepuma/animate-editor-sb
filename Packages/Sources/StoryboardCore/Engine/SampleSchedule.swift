/// Decides which sounds to start as the preview clock moves.
///
/// Pure on purpose: the clock it follows runs before 0 and after the track as
/// well as inside it, so it cannot lean on any audio node's own timeline, and
/// CI has no audio device to test one against. Whoever plays the sounds only
/// does what this hands back.
public struct SampleSchedule: Sendable {
    /// A sound to start `delay` wall-clock milliseconds from now.
    public struct Fire: Equatable, Sendable {
        public var sample: StoryboardSample
        public var delay: Double
    }

    /// How far ahead of the clock a sample is handed over, in song ms. Frames
    /// arrive every 16 ms; starting a sound at a scheduled host time rather
    /// than "now" is what keeps it from landing on the frame grid.
    public static let lookahead: Double = 100
    /// A sample this late (wall ms) still plays, immediately; later than this
    /// it is dropped, because a clap well after the beat is worse than none.
    public static let lateTolerance: Double = 50

    /// Kept in time order, ties in the order given.
    public var samples: [StoryboardSample] = [] {
        didSet {
            samples = samples.enumerated()
                .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
                .map(\.element)
        }
    }

    private var cursor: Double = 0
    private var includesCursor = false

    public init() {}

    /// Moves the window to start at `time`: a seek, a loop, a start.
    ///
    /// `inclusive` says whether a sample sitting exactly on `time` still has to
    /// play. Landing on one by seeking or starting there should sound it;
    /// resuming from a pause should not, since it sounded before the pause.
    public mutating func reset(at time: Double, inclusive: Bool) {
        cursor = time
        includesCursor = inclusive
    }

    /// The samples whose time falls in (cursor, `time` + `lookahead`].
    public mutating func advance(to time: Double, rate: Float, lookahead: Double) -> [Fire] {
        let end = time + lookahead
        guard end >= cursor, rate > 0 else { return [] }

        var fires: [Fire] = []
        for sample in samples {
            if sample.time > end { break }
            let inWindow = sample.time > cursor || (includesCursor && sample.time == cursor)
            guard inWindow else { continue }

            var delay = (sample.time - time) / Double(rate)
            if delay < 0 {
                guard -delay <= Self.lateTolerance else { continue }
                delay = 0
            }
            fires.append(Fire(sample: sample, delay: delay))
        }
        cursor = end
        includesCursor = false
        return fires
    }
}
