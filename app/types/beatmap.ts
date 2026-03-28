// ─── Timing Points ───────────────────────────────────────────────────────────

/** A red line (uninherited timing point) — defines BPM and meter */
export interface UninheritedTimingPoint {
    /** Start time in milliseconds */
    time: number
    /** Milliseconds per beat (60000 / BPM) */
    beatLength: number
    /** Derived BPM = 60000 / beatLength */
    bpm: number
    /** Beats per measure (e.g. 4 for 4/4 time) */
    meter: number
    /** Whether kiai is active at this timing point */
    kiai: boolean
}

/** A green line (inherited timing point) — modifies SV and effects */
export interface InheritedTimingPoint {
    /** Start time in milliseconds */
    time: number
    /** Slider velocity multiplier = -100 / beatLength */
    svMultiplier: number
    /** Whether kiai is active at this timing point */
    kiai: boolean
}

// ─── Break Period ────────────────────────────────────────────────────────────

export interface BreakPeriod {
    startTime: number
    endTime: number
}

// ─── Kiai Section ────────────────────────────────────────────────────────────

/** A contiguous kiai time range, derived from timing points */
export interface KiaiSection {
    startTime: number
    endTime: number
}

// ─── Beatmap Metadata ────────────────────────────────────────────────────────

export interface BeatmapMetadata {
    title: string
    titleUnicode: string
    artist: string
    artistUnicode: string
    creator: string
    version: string
}

// ─── Parsed Beatmap ──────────────────────────────────────────────────────────

/** The subset of .osu data relevant to the timeline */
export interface BeatmapTimingData {
    metadata: BeatmapMetadata
    audioFilename: string
    /** Red lines only, sorted by time ascending */
    uninheritedPoints: UninheritedTimingPoint[]
    /** Break periods from the [Events] section */
    breaks: BreakPeriod[]
    /** Pre-computed contiguous kiai sections */
    kiaiSections: KiaiSection[]
}
