import type {
    BeatmapTimingData,
    BeatmapMetadata,
    UninheritedTimingPoint,
    InheritedTimingPoint,
    BreakPeriod,
    KiaiSection,
} from '~/types'

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Parses the relevant sections of a .osu beatmap file.
 * Extracts: [General], [Metadata], [TimingPoints], [Events] (breaks only).
 */
export function parseOsu(source: string): BeatmapTimingData {
    const lines = source.split(/\r?\n/)

    let section = ''
    let audioFilename = ''
    const metaRaw: Record<string, string> = {}
    const uninheritedPoints: UninheritedTimingPoint[] = []
    // All timing points (both red and green) for kiai computation
    const allPoints: Array<{ time: number; kiai: boolean }> = []
    const breaks: BreakPeriod[] = []

    for (const raw of lines) {
        const line = raw.trim()

        // Section headers
        if (line.startsWith('[') && line.endsWith(']')) {
            section = line
            continue
        }

        if (!line || line.startsWith('//')) continue

        switch (section) {
            case '[General]': {
                const [key, ...rest] = line.split(':')
                const value = rest.join(':').trim()
                if (key?.trim() === 'AudioFilename') audioFilename = value
                break
            }

            case '[Metadata]': {
                const colonIdx = line.indexOf(':')
                if (colonIdx !== -1) {
                    metaRaw[line.slice(0, colonIdx).trim()] = line.slice(colonIdx + 1).trim()
                }
                break
            }

            case '[TimingPoints]': {
                parseTimingPointLine(line, uninheritedPoints, allPoints)
                break
            }

            case '[Events]': {
                parseBreakLine(line, breaks)
                break
            }
        }
    }

    // Sort by time
    uninheritedPoints.sort((a, b) => a.time - b.time)
    allPoints.sort((a, b) => a.time - b.time)
    breaks.sort((a, b) => a.startTime - b.startTime)

    const metadata: BeatmapMetadata = {
        title: metaRaw['Title'] ?? '',
        titleUnicode: metaRaw['TitleUnicode'] ?? metaRaw['Title'] ?? '',
        artist: metaRaw['Artist'] ?? '',
        artistUnicode: metaRaw['ArtistUnicode'] ?? metaRaw['Artist'] ?? '',
        creator: metaRaw['Creator'] ?? '',
        version: metaRaw['Version'] ?? '',
    }

    const kiaiSections = computeKiaiSections(allPoints)

    return {
        metadata,
        audioFilename,
        uninheritedPoints,
        breaks,
        kiaiSections,
    }
}

// ─── Internals ────────────────────────────────────────────────────────────────

/**
 * Parses a single TimingPoints line.
 * Format: time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects
 */
function parseTimingPointLine(
    line: string,
    uninherited: UninheritedTimingPoint[],
    all: Array<{ time: number; kiai: boolean }>,
): void {
    const parts = line.split(',')
    if (parts.length < 2) return

    const time = Math.round(parseFloat(parts[0] ?? '0'))
    const beatLength = parseFloat(parts[1] ?? '0')
    const meter = parseInt(parts[2] ?? '4', 10) || 4
    const isUninherited = (parseInt(parts[6] ?? '1', 10)) === 1
    const effects = parseInt(parts[7] ?? '0', 10) || 0
    const kiai = (effects & 1) === 1

    all.push({ time, kiai })

    if (isUninherited && beatLength > 0) {
        uninherited.push({
            time,
            beatLength,
            bpm: 60000 / beatLength,
            meter,
            kiai,
        })
    }
}

/**
 * Parses a break event line from the [Events] section.
 * Format: 2,startTime,endTime  or  Break,startTime,endTime
 */
function parseBreakLine(line: string, breaks: BreakPeriod[]): void {
    const parts = line.split(',')
    const type = parts[0]?.trim()
    if (type !== '2' && type !== 'Break') return

    const startTime = parseInt(parts[1] ?? '0', 10)
    const endTime = parseInt(parts[2] ?? '0', 10)
    if (endTime > startTime) {
        breaks.push({ startTime, endTime })
    }
}

/**
 * Walks all timing points in time order and computes contiguous kiai sections.
 * Kiai state persists from one timing point to the next.
 */
function computeKiaiSections(
    allPoints: Array<{ time: number; kiai: boolean }>,
): KiaiSection[] {
    const sections: KiaiSection[] = []
    let kiaiStart = -1

    for (const point of allPoints) {
        if (point.kiai && kiaiStart === -1) {
            kiaiStart = point.time
        } else if (!point.kiai && kiaiStart !== -1) {
            sections.push({ startTime: kiaiStart, endTime: point.time })
            kiaiStart = -1
        }
    }

    // If kiai was still on at the last timing point, close it at a large value.
    // The renderer will clamp to durationMs.
    if (kiaiStart !== -1) {
        const lastTime = allPoints[allPoints.length - 1]?.time ?? kiaiStart
        sections.push({ startTime: kiaiStart, endTime: lastTime + 60000 })
    }

    return sections
}
