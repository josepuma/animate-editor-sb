/// Title, artist and difficulty name from a `.osu` file's `[Metadata]`.
public struct BeatmapMetadata: Sendable, Equatable {
    public var title: String
    public var titleUnicode: String
    public var artist: String
    public var artistUnicode: String
    public var creator: String
    /// Difficulty name.
    public var version: String

    public init(
        title: String = "",
        titleUnicode: String = "",
        artist: String = "",
        artistUnicode: String = "",
        creator: String = "",
        version: String = "",
    ) {
        self.title = title
        self.titleUnicode = titleUnicode
        self.artist = artist
        self.artistUnicode = artistUnicode
        self.creator = creator
        self.version = version
    }

    /// The title as its own language writes it.
    ///
    /// `Title` holds a romanisation for searching; `TitleUnicode` holds what the
    /// artist actually called the song, which is what should be shown.
    public var displayTitle: String {
        titleUnicode.isEmpty ? title : titleUnicode
    }

    /// The artist's own name, for the same reason.
    public var displayArtist: String {
        artistUnicode.isEmpty ? artist : artistUnicode
    }

    /// `Artist - Title`, or whichever half is present.
    public var displayName: String {
        let artist = displayArtist
        let title = displayTitle

        return switch (artist.isEmpty, title.isEmpty) {
        case (false, false): "\(artist) - \(title)"
        case (true, false): title
        case (false, true): artist
        case (true, true): ""
        }
    }
}

/// A red timing point: sets the tempo from `time` onwards.
public struct UninheritedTimingPoint: Sendable, Equatable {
    public var time: Double
    /// Milliseconds per beat.
    public var beatLength: Double
    public var bpm: Double
    /// Beats per measure.
    public var meter: Int
    public var kiai: Bool

    public init(time: Double, beatLength: Double, meter: Int, kiai: Bool) {
        self.time = time
        self.beatLength = beatLength
        bpm = beatLength > 0 ? 60_000 / beatLength : 0
        self.meter = meter
        self.kiai = kiai
    }
}

/// A stretch with no notes.
public struct BreakPeriod: Sendable, Equatable {
    public var startTime: Double
    public var endTime: Double

    public init(startTime: Double, endTime: Double) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// A stretch flagged as kiai, the map's highlight section.
public struct KiaiSection: Sendable, Equatable {
    public var startTime: Double
    public var endTime: Double

    public init(startTime: Double, endTime: Double) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Everything the editor needs from a `.osu` file besides its storyboard.
public struct BeatmapTimingData: Sendable, Equatable {
    public var metadata: BeatmapMetadata
    /// Audio file name, relative to the beatmap folder.
    public var audioFilename: String
    /// Whether the storyboard was authored for a 16:9 frame.
    ///
    /// osu! draws a 4:3 storyboard pillarboxed rather than stretched, so a map
    /// with this off has sprites positioned for the narrower stage — laying
    /// them across a wide one puts everything in the wrong place.
    public var isWidescreen: Bool
    /// Red timing points, sorted by time.
    public var uninheritedPoints: [UninheritedTimingPoint]
    public var breaks: [BreakPeriod]
    public var kiaiSections: [KiaiSection]

    public init(
        metadata: BeatmapMetadata = BeatmapMetadata(),
        audioFilename: String = "",
        isWidescreen: Bool = false,
        uninheritedPoints: [UninheritedTimingPoint] = [],
        breaks: [BreakPeriod] = [],
        kiaiSections: [KiaiSection] = [],
    ) {
        self.metadata = metadata
        self.audioFilename = audioFilename
        self.isWidescreen = isWidescreen
        self.uninheritedPoints = uninheritedPoints
        self.breaks = breaks
        self.kiaiSections = kiaiSections
    }

    /// Tempo at `time`, or the first point when `time` precedes them all.
    public func timingPoint(at time: Double) -> UninheritedTimingPoint? {
        guard !uninheritedPoints.isEmpty else { return nil }

        var low = 0
        var high = uninheritedPoints.count - 1
        var result: UninheritedTimingPoint?

        while low <= high {
            let mid = (low + high) / 2
            if uninheritedPoints[mid].time <= time {
                result = uninheritedPoints[mid]
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result ?? uninheritedPoints.first
    }
}
