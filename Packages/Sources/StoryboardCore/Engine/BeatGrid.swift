import Foundation

/// One tick of the beat grid.
public struct BeatLine: Sendable, Equatable {
    /// Absolute time in milliseconds.
    public let time: Double
    /// True on a downbeat — the first beat of a measure.
    public let isMajor: Bool

    public init(time: Double, isMajor: Bool) {
        self.time = time
        self.isMajor = isMajor
    }
}

/// Beat snapping and grid generation over a beatmap's timing points.
///
/// Ported from `app/composables/useTiming.ts`. Tempo can change mid-map, so
/// every operation resolves the timing point governing the moment in question
/// rather than assuming one tempo throughout.
public struct BeatGrid: Sendable {
    public let timing: BeatmapTimingData
    /// Subdivisions per beat: 1 for whole beats, 4 for sixteenths.
    public let divisor: Int

    public init(timing: BeatmapTimingData, divisor: Int = 4) {
        self.timing = timing
        self.divisor = max(1, divisor)
    }

    public var isEmpty: Bool { timing.uninheritedPoints.isEmpty }

    /// Tempo of the first timing point, the map's nominal BPM.
    public var primaryBPM: Double? { timing.uninheritedPoints.first?.bpm }

    public func bpm(at time: Double) -> Double {
        timing.timingPoint(at: time)?.bpm ?? 0
    }

    // ─── Snapping ────────────────────────────────────────────────────────────

    /// Rounds `time` to the nearest subdivision.
    public func snap(_ time: Double) -> Double {
        guard let point = timing.timingPoint(at: time) else { return time }
        let interval = point.beatLength / Double(divisor)
        guard interval > 0 else { return time }

        let elapsed = time - point.time
        return ((elapsed / interval).rounded() * interval + point.time).rounded()
    }

    /// The first subdivision after `time`.
    ///
    /// Stops at the next timing point rather than stepping past it, so the grid
    /// stays aligned across a tempo change.
    public func nextBeat(after time: Double) -> Double {
        guard let point = timing.timingPoint(at: time) else { return time }
        let interval = point.beatLength / Double(divisor)
        guard interval > 0 else { return time }

        let elapsed = time - point.time
        let currentIndex = (elapsed / interval).rounded()
        let currentBeat = currentIndex * interval + point.time
        // Half a millisecond of tolerance keeps a beat we are already sitting
        // on from being returned again.
        let next = currentBeat <= time + 0.5 ? currentBeat + interval : currentBeat

        if let following = nextTimingPoint(after: point), next >= following.time {
            return following.time
        }
        return next.rounded()
    }

    /// The last subdivision before `time`.
    public func previousBeat(before time: Double) -> Double {
        guard var point = timing.timingPoint(at: time) else { return time }

        // Standing exactly on a timing point means the beat before it belongs
        // to the previous section, at whatever tempo that ran.
        if abs(time - point.time) < 0.5, let earlier = previousTimingPoint(before: point) {
            point = earlier
        }

        let interval = point.beatLength / Double(divisor)
        guard interval > 0 else { return time }

        let elapsed = time - point.time
        var previous = (elapsed / interval - 0.001).rounded(.down) * interval + point.time

        // Sitting exactly on a beat means stepping back a further interval.
        if abs(previous - time) < 0.5 { previous -= interval }

        // Never step back past the section's own start.
        return Swift.max(previous, point.time).rounded()
    }

    // ─── Grid ────────────────────────────────────────────────────────────────

    /// Beat lines covering `range`, in order.
    ///
    /// Only the requested span is generated, so a zoomed-out view of a long map
    /// costs no more than a zoomed-in one.
    public func lines(in range: ClosedRange<Double>) -> [BeatLine] {
        let points = timing.uninheritedPoints
        guard !points.isEmpty else { return [] }

        var lines: [BeatLine] = []
        let start = range.lowerBound
        let end = range.upperBound

        // Start from the timing point governing the range's beginning.
        var index = points.lastIndex { $0.time <= start } ?? 0

        while index < points.count {
            let point = points[index]
            guard point.time <= end else { break }

            let interval = point.beatLength / Double(divisor)
            guard interval > 0 else {
                index += 1
                continue
            }

            let followingTime = index + 1 < points.count ? points[index + 1].time : end + 1
            let sectionStart = Swift.max(start, point.time)
            let sectionEnd = Swift.min(end, followingTime)

            let elapsed = sectionStart - point.time
            var beatIndex = (elapsed / interval).rounded(.down)
            var beatTime = point.time + beatIndex * interval

            if beatTime < sectionStart - 0.5 {
                beatIndex += 1
                beatTime = point.time + beatIndex * interval
            }

            let beatsPerMeasure = Double(point.meter * divisor)

            while beatTime <= sectionEnd + 0.5 {
                let isMajor = beatsPerMeasure > 0
                    && beatIndex.truncatingRemainder(dividingBy: beatsPerMeasure) == 0
                lines.append(BeatLine(time: beatTime.rounded(), isMajor: isMajor))
                beatIndex += 1
                beatTime = point.time + beatIndex * interval
            }

            index += 1
        }

        return lines
    }

    // ─── Timing point navigation ─────────────────────────────────────────────

    private func nextTimingPoint(after point: UninheritedTimingPoint) -> UninheritedTimingPoint? {
        timing.uninheritedPoints.first { $0.time > point.time }
    }

    private func previousTimingPoint(before point: UninheritedTimingPoint) -> UninheritedTimingPoint? {
        timing.uninheritedPoints.last { $0.time < point.time }
    }
}
