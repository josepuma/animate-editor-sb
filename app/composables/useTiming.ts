import { ref, computed, readonly } from 'vue'
import { parseOsu } from '~/lib/parser/osu'
import type { BeatmapTimingData, UninheritedTimingPoint } from '~/types'

// ─── Types ───────────────────────────────────────────────────────────────────

export interface BeatLine {
    /** Absolute time in ms */
    ms: number
    /** True for downbeats (beat 1 of a measure) */
    isMajor: boolean
}

// ─── Composable ──────────────────────────────────────────────────────────────

export function useTiming() {
    const timingData = ref<BeatmapTimingData | null>(null)
    const beatDivisor = ref(4)

    // ── Load / clear ─────────────────────────────────────────────────────────

    function loadFromOsu(content: string): void {
        timingData.value = parseOsu(content)
    }

    function clear(): void {
        timingData.value = null
    }

    // ── Derived ──────────────────────────────────────────────────────────────

    const primaryBpm = computed(() =>
        timingData.value?.uninheritedPoints[0]?.bpm ?? null,
    )

    const hasTimingData = computed(() =>
        timingData.value !== null && timingData.value.uninheritedPoints.length > 0,
    )

    // ── Timing point lookup (binary search) ──────────────────────────────────

    /**
     * Returns the active uninherited (red-line) timing point at the given ms.
     * Uses binary search for O(log n) lookup.
     */
    function getTimingPointAt(ms: number): UninheritedTimingPoint | null {
        const points = timingData.value?.uninheritedPoints
        if (!points || points.length === 0) return null

        // Binary search: find rightmost point with time <= ms
        let lo = 0
        let hi = points.length - 1
        let result = 0

        while (lo <= hi) {
            const mid = (lo + hi) >>> 1
            if (points[mid]!.time <= ms) {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        return points[result]!
    }

    // ── Beat navigation ──────────────────────────────────────────────────────

    /**
     * Returns the ms value of the next beat boundary after `ms`.
     * Respects beatDivisor (1/1, 1/2, 1/4, etc.)
     */
    function nextBeat(ms: number): number {
        const tp = getTimingPointAt(ms)
        if (!tp) return ms

        const interval = tp.beatLength / beatDivisor.value
        const elapsed = ms - tp.time
        // Snap to current beat, then add one interval
        const currentBeatIdx = Math.round(elapsed / interval)
        const currentBeatMs = currentBeatIdx * interval + tp.time
        // If we're already on or past this beat, go to the next one
        const nextMs = currentBeatMs <= ms + 0.5 ? currentBeatMs + interval : currentBeatMs

        // Clamp to next timing point boundary if applicable
        const points = timingData.value!.uninheritedPoints
        const idx = points.indexOf(tp)
        if (idx < points.length - 1) {
            const nextTp = points[idx + 1]!
            if (nextMs >= nextTp.time) return nextTp.time
        }

        return Math.round(nextMs)
    }

    /**
     * Returns the ms value of the previous beat boundary before `ms`.
     */
    function prevBeat(ms: number): number {
        const tp = getTimingPointAt(ms)
        if (!tp) return ms

        const interval = tp.beatLength / beatDivisor.value
        const elapsed = ms - tp.time
        let prevMs = Math.floor(elapsed / interval - 0.001) * interval + tp.time

        // If we're exactly on a beat, go one more back
        if (Math.abs(prevMs - ms) < 0.5) {
            prevMs -= interval
        }

        // Don't go before this timing point's start — jump to prev timing point
        if (prevMs < tp.time) {
            const points = timingData.value!.uninheritedPoints
            const idx = points.indexOf(tp)
            if (idx > 0) {
                const prevTp = points[idx - 1]!
                const prevInterval = prevTp.beatLength / beatDivisor.value
                // Snap to the last beat of the previous timing section
                const prevElapsed = tp.time - prevTp.time
                return Math.round(Math.floor(prevElapsed / prevInterval) * prevInterval + prevTp.time)
            }
            return Math.round(tp.time)
        }

        return Math.round(prevMs)
    }

    /**
     * Snaps a ms value to the nearest beat boundary.
     */
    function snapToBeat(ms: number): number {
        const tp = getTimingPointAt(ms)
        if (!tp) return ms

        const interval = tp.beatLength / beatDivisor.value
        const elapsed = ms - tp.time
        return Math.round(Math.round(elapsed / interval) * interval + tp.time)
    }

    /**
     * Returns the BPM at a given ms position.
     */
    function bpmAt(ms: number): number {
        return getTimingPointAt(ms)?.bpm ?? 0
    }

    // ── Beat line generation (for canvas rendering) ──────────────────────────

    /**
     * Generates beat line positions between startMs and endMs.
     * Returns an array of { ms, isMajor } objects.
     * isMajor = true for downbeats (beat 1 of a measure).
     */
    function getBeatLines(startMs: number, endMs: number): BeatLine[] {
        const points = timingData.value?.uninheritedPoints
        if (!points || points.length === 0) return []

        const lines: BeatLine[] = []
        const divisor = beatDivisor.value

        // Find the first relevant timing point (the one active at startMs)
        let tpIdx = 0
        for (let i = points.length - 1; i >= 0; i--) {
            if (points[i]!.time <= startMs) {
                tpIdx = i
                break
            }
        }

        // Walk through timing points that overlap [startMs, endMs]
        while (tpIdx < points.length) {
            const tp = points[tpIdx]!
            const nextTpTime = tpIdx + 1 < points.length
                ? points[tpIdx + 1]!.time
                : endMs + 1

            if (tp.time > endMs) break

            const interval = tp.beatLength / divisor
            if (interval <= 0) { tpIdx++; continue }

            const beatsPerMeasure = tp.meter * divisor
            const sectionStart = Math.max(startMs, tp.time)

            // Find the first beat at or after sectionStart
            const elapsed = sectionStart - tp.time
            let beatIndex = Math.floor(elapsed / interval)
            let beatMs = tp.time + beatIndex * interval

            // If beatMs is before sectionStart, advance
            if (beatMs < sectionStart - 0.5) {
                beatIndex++
                beatMs = tp.time + beatIndex * interval
            }

            const sectionEnd = Math.min(endMs, nextTpTime)

            while (beatMs <= sectionEnd + 0.5) {
                const isMajor = beatIndex % beatsPerMeasure === 0
                lines.push({ ms: Math.round(beatMs), isMajor })
                beatIndex++
                beatMs = tp.time + beatIndex * interval
            }

            tpIdx++
        }

        return lines
    }

    return {
        timingData: readonly(timingData),
        beatDivisor,
        primaryBpm,
        hasTimingData,
        loadFromOsu,
        clear,
        getTimingPointAt,
        nextBeat,
        prevBeat,
        snapToBeat,
        bpmAt,
        getBeatLines,
    }
}
