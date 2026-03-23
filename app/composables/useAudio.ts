import { ref, computed, readonly } from 'vue'

// ─── Composable ──────────────────────────────────────────────────────────────

export function useAudio() {
    const isPlaying = ref(false)
    const currentMs = ref(0)
    const durationMs = ref(0)
    const volume = ref(1)

    let audioCtx: AudioContext | null = null
    let sourceNode: AudioBufferSourceNode | null = null
    let audioBuffer: AudioBuffer | null = null

    /** Timestamp (AudioContext.currentTime) when playback started */
    let playStartedAt = 0
    /** Audio time (ms) at which playback started */
    let playOffsetMs = 0
    /** rAF handle */
    let rafId: number | null = null

    // ── Load ──────────────────────────────────────────────────────────────────

    async function loadFromHandle(handle: FileSystemFileHandle): Promise<void> {
        stop()
        const ctx = getAudioContext()
        const file = await handle.getFile()
        const arrayBuffer = await file.arrayBuffer()
        audioBuffer = await ctx.decodeAudioData(arrayBuffer)
        durationMs.value = audioBuffer.duration * 1000
        currentMs.value = 0
    }

    async function loadFromUrl(url: string): Promise<void> {
        stop()
        const ctx = getAudioContext()
        const res = await fetch(url)
        const arrayBuffer = await res.arrayBuffer()
        audioBuffer = await ctx.decodeAudioData(arrayBuffer)
        durationMs.value = audioBuffer.duration * 1000
        currentMs.value = 0
    }

    // ── Transport ─────────────────────────────────────────────────────────────

    function play(): void {
        if (!audioBuffer || isPlaying.value) return

        const ctx = getAudioContext()
        sourceNode = ctx.createBufferSource()
        sourceNode.buffer = audioBuffer

        const gainNode = ctx.createGain()
        gainNode.gain.value = volume.value
        sourceNode.connect(gainNode).connect(ctx.destination)

        const offsetSec = currentMs.value / 1000
        playStartedAt = ctx.currentTime
        playOffsetMs = currentMs.value

        sourceNode.start(0, offsetSec)
        isPlaying.value = true

        sourceNode.onended = () => {
            if (isPlaying.value) stop()
        }

        startTick()
    }

    function pause(): void {
        if (!isPlaying.value) return
        isPlaying.value = false  // set before stopSource so onended guard doesn't call stop()
        stopSource()
        stopTick()
    }

    function stop(): void {
        stopSource()
        stopTick()
        isPlaying.value = false
        currentMs.value = 0
    }

    function seek(ms: number): void {
        const wasPlaying = isPlaying.value
        if (wasPlaying) pause()
        currentMs.value = Math.max(0, Math.min(ms, durationMs.value))
        if (wasPlaying) play()
    }

    function setVolume(v: number): void {
        volume.value = Math.max(0, Math.min(1, v))
    }

    // ── Tick ──────────────────────────────────────────────────────────────────

    function startTick(): void {
        const tick = () => {
            if (!isPlaying.value || !audioCtx) return
            const elapsed = (audioCtx.currentTime - playStartedAt) * 1000
            currentMs.value = Math.min(playOffsetMs + elapsed, durationMs.value)
            rafId = requestAnimationFrame(tick)
        }
        rafId = requestAnimationFrame(tick)
    }

    function stopTick(): void {
        if (rafId !== null) {
            cancelAnimationFrame(rafId)
            rafId = null
        }
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    function getAudioContext(): AudioContext {
        if (!audioCtx) audioCtx = new AudioContext()
        return audioCtx
    }

    function stopSource(): void {
        if (sourceNode) {
            sourceNode.onended = null  // prevent stale async onended from resetting state
            try { sourceNode.stop() } catch { }
            sourceNode.disconnect()
            sourceNode = null
        }
    }

    /** Fully clears audio state (call when opening a new project). */
    function unload(): void {
        stop()
        audioBuffer = null
        durationMs.value = 0
    }

    function destroy(): void {
        stop()
        audioCtx?.close()
        audioCtx = null
        audioBuffer = null
        durationMs.value = 0
    }

    return {
        // State (readonly)
        isPlaying: readonly(isPlaying),
        currentMs: readonly(currentMs),
        durationMs: readonly(durationMs),
        volume: readonly(volume),

        // Derived
        progress: computed(() =>
            durationMs.value > 0 ? currentMs.value / durationMs.value : 0,
        ),

        // Actions
        loadFromHandle,
        loadFromUrl,
        play,
        pause,
        stop,
        seek,
        setVolume,
        unload,
        destroy,
    }
}
