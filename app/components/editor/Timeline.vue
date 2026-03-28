<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, computed } from 'vue'
import type { BeatmapTimingData, KiaiSection, BreakPeriod } from '~/types'
import type { BeatLine } from '~/composables/useTiming'

// ─── Props ────────────────────────────────────────────────────────────────────

const props = defineProps<{
    currentMs: number
    durationMs: number
    hasAudio: boolean
    isPlaying: boolean
    timingData: BeatmapTimingData | null
    beatDivisor: number
    getBeatLines: (startMs: number, endMs: number) => BeatLine[]
    kiaiSections: KiaiSection[]
    breaks: BreakPeriod[]
}>()

const emit = defineEmits<{
    (e: 'seek', ms: number): void
}>()

// ─── Constants ────────────────────────────────────────────────────────────────

const MIN_MS_PER_PX = 0.5
const MAX_MS_PER_PX = 50
const DEFAULT_MS_PER_PX = 5
const TIMELINE_HEIGHT = 48

// ─── State ────────────────────────────────────────────────────────────────────

const containerRef = ref<HTMLDivElement | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const msPerPx = ref(DEFAULT_MS_PER_PX)
const viewportCenterMs = ref(0)
const isDragging = ref(false)
const followPlayback = ref(true)

let canvasWidth = 0
let canvasHeight = TIMELINE_HEIGHT
let dpr = 1
let rafId = 0

const viewportStartMs = computed(() =>
    viewportCenterMs.value - (canvasWidth / 2) * msPerPx.value,
)
const viewportEndMs = computed(() =>
    viewportCenterMs.value + (canvasWidth / 2) * msPerPx.value,
)

// ─── Canvas setup ─────────────────────────────────────────────────────────────

function setupCanvas() {
    const container = containerRef.value
    const canvas = canvasRef.value
    if (!container || !canvas) return

    dpr = window.devicePixelRatio || 1
    canvasWidth = container.clientWidth
    canvasHeight = TIMELINE_HEIGHT

    canvas.width = canvasWidth * dpr
    canvas.height = canvasHeight * dpr
    canvas.style.width = `${canvasWidth}px`
    canvas.style.height = `${canvasHeight}px`
}

// ─── Drawing ──────────────────────────────────────────────────────────────────

function draw() {
    const canvas = canvasRef.value
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    ctx.save()
    ctx.scale(dpr, dpr)

    const w = canvasWidth
    const h = canvasHeight
    const startMs = viewportCenterMs.value - (w / 2) * msPerPx.value
    const endMs = viewportCenterMs.value + (w / 2) * msPerPx.value

    // Helper: ms → canvas x
    const msToX = (ms: number) => (ms - startMs) / msPerPx.value

    // 1. Background
    ctx.fillStyle = '#0f0f17'
    ctx.fillRect(0, 0, w, h)

    // 2. Break periods (darker overlay)
    ctx.fillStyle = 'rgba(0, 0, 0, 0.45)'
    for (const bp of props.breaks) {
        if (bp.endTime < startMs || bp.startTime > endMs) continue
        const x0 = Math.max(0, msToX(bp.startTime))
        const x1 = Math.min(w, msToX(bp.endTime))
        ctx.fillRect(x0, 0, x1 - x0, h)
    }

    // 3. Kiai sections (warm highlight)
    ctx.fillStyle = 'rgba(255, 170, 0, 0.10)'
    for (const ks of props.kiaiSections) {
        if (ks.endTime < startMs || ks.startTime > endMs) continue
        const x0 = Math.max(0, msToX(ks.startTime))
        const x1 = Math.min(w, msToX(ks.endTime))
        ctx.fillRect(x0, 0, x1 - x0, h)
    }

    // 4. Beat lines
    if (props.timingData && props.timingData.uninheritedPoints.length > 0) {
        const lines = props.getBeatLines(startMs, endMs)
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]!
            const x = msToX(line.ms)
            if (x < -1 || x > w + 1) continue

            if (line.isMajor) {
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.45)'
                ctx.lineWidth = 1.5
            } else {
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)'
                ctx.lineWidth = 0.5
            }
            ctx.beginPath()
            ctx.moveTo(x, 0)
            ctx.lineTo(x, h)
            ctx.stroke()
        }
    }

    // 5. Time labels
    const labelInterval = computeLabelInterval(msPerPx.value)
    if (labelInterval > 0) {
        ctx.fillStyle = 'rgba(255, 255, 255, 0.35)'
        ctx.font = '10px monospace'
        ctx.textBaseline = 'bottom'

        const firstLabel = Math.ceil(startMs / labelInterval) * labelInterval
        for (let t = firstLabel; t <= endMs; t += labelInterval) {
            const x = msToX(t)
            if (x < 0 || x > w) continue
            ctx.fillText(formatTime(t), x + 3, h - 2)
        }
    }

    // 6. Duration boundary
    if (props.durationMs > 0) {
        // Dim area after song ends
        const durationX = msToX(props.durationMs)
        if (durationX < w) {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.6)'
            ctx.fillRect(Math.max(0, durationX), 0, w - durationX, h)
        }
        // Dim area before song starts
        const zeroX = msToX(0)
        if (zeroX > 0) {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.6)'
            ctx.fillRect(0, 0, zeroX, h)
        }
    }

    // 7. Playhead
    const playheadX = msToX(props.currentMs)
    if (playheadX >= -2 && playheadX <= w + 2) {
        // Line
        ctx.strokeStyle = '#a78bfa'
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.moveTo(playheadX, 0)
        ctx.lineTo(playheadX, h)
        ctx.stroke()

        // Triangle marker at top
        ctx.fillStyle = '#a78bfa'
        ctx.beginPath()
        ctx.moveTo(playheadX, 0)
        ctx.lineTo(playheadX - 5, -1)
        ctx.lineTo(playheadX + 5, -1)
        ctx.closePath()
        ctx.fill()

        // Small time badge near playhead
        ctx.fillStyle = 'rgba(167, 139, 250, 0.9)'
        ctx.font = '9px monospace'
        ctx.textBaseline = 'top'
        const label = formatTimePrecise(props.currentMs)
        const labelW = ctx.measureText(label).width + 6
        const badgeX = Math.min(Math.max(playheadX - labelW / 2, 0), w - labelW)
        ctx.fillStyle = 'rgba(30, 20, 50, 0.85)'
        ctx.fillRect(badgeX, 2, labelW, 14)
        ctx.fillStyle = '#c4b5fd'
        ctx.fillText(label, badgeX + 3, 3)
    }

    ctx.restore()
}

// ─── Animation loop ───────────────────────────────────────────────────────────

function tick() {
    // Follow playhead during playback (unless user is dragging)
    if (followPlayback.value && !isDragging.value && props.hasAudio) {
        viewportCenterMs.value = props.currentMs
    }

    draw()
    rafId = requestAnimationFrame(tick)
}

// ─── Interaction ──────────────────────────────────────────────────────────────

function xToMs(clientX: number): number {
    const canvas = canvasRef.value
    if (!canvas) return 0
    const rect = canvas.getBoundingClientRect()
    const x = clientX - rect.left
    return viewportCenterMs.value + (x - canvasWidth / 2) * msPerPx.value
}

function onPointerDown(e: PointerEvent) {
    if (!props.hasAudio) return
    isDragging.value = true
    const ms = clampMs(xToMs(e.clientX))
    emit('seek', ms)
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
}

function onPointerMove(e: PointerEvent) {
    if (!isDragging.value) return
    const ms = clampMs(xToMs(e.clientX))
    emit('seek', ms)
}

function onPointerUp() {
    if (!isDragging.value) return
    isDragging.value = false
    // Re-enable follow mode
    followPlayback.value = true
}

function onWheel(e: WheelEvent) {
    e.preventDefault()

    if (e.ctrlKey || e.metaKey) {
        // Zoom around mouse cursor
        const canvas = canvasRef.value
        if (!canvas) return
        const rect = canvas.getBoundingClientRect()
        const mouseX = e.clientX - rect.left
        const mouseMs = viewportCenterMs.value + (mouseX - canvasWidth / 2) * msPerPx.value

        const factor = e.deltaY > 0 ? 1.15 : 1 / 1.15
        msPerPx.value = Math.min(MAX_MS_PER_PX, Math.max(MIN_MS_PER_PX, msPerPx.value * factor))

        // Adjust center so the ms under the cursor stays in place
        viewportCenterMs.value = mouseMs - (mouseX - canvasWidth / 2) * msPerPx.value
        followPlayback.value = false
    } else {
        // Horizontal pan
        const panMs = e.deltaY * msPerPx.value * 3
        viewportCenterMs.value += panMs
        followPlayback.value = false
    }
}

function clampMs(ms: number): number {
    return Math.max(0, Math.min(props.durationMs, ms))
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatTime(ms: number): string {
    const s = Math.floor(Math.abs(ms) / 1000)
    const sign = ms < 0 ? '-' : ''
    return `${sign}${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

function formatTimePrecise(ms: number): string {
    const totalMs = Math.abs(Math.round(ms))
    const s = Math.floor(totalMs / 1000)
    const frac = totalMs % 1000
    const sign = ms < 0 ? '-' : ''
    return `${sign}${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}.${String(frac).padStart(3, '0')}`
}

function computeLabelInterval(msPerPx: number): number {
    // Choose a label interval that keeps labels spaced ~100px apart
    const targetMs = msPerPx * 100
    const intervals = [500, 1000, 2000, 5000, 10000, 30000, 60000]
    for (const iv of intervals) {
        if (iv >= targetMs) return iv
    }
    return 60000
}

// ─── Watchers ─────────────────────────────────────────────────────────────────

// Re-enable follow when playback starts
watch(
    () => props.isPlaying,
    (playing) => {
        if (playing) followPlayback.value = true
    },
)

// When audio loads, center on 0
watch(
    () => props.durationMs,
    () => {
        if (props.durationMs > 0) {
            viewportCenterMs.value = 0
            followPlayback.value = true
        }
    },
)

// ─── Lifecycle ────────────────────────────────────────────────────────────────

let resizeObserver: ResizeObserver | null = null

onMounted(() => {
    setupCanvas()
    rafId = requestAnimationFrame(tick)

    if (containerRef.value) {
        resizeObserver = new ResizeObserver(() => {
            setupCanvas()
            draw()
        })
        resizeObserver.observe(containerRef.value)
    }

    // Center on current position
    viewportCenterMs.value = props.currentMs
})

onUnmounted(() => {
    cancelAnimationFrame(rafId)
    resizeObserver?.disconnect()
})
</script>

<template>
    <div
        ref="containerRef"
        class="relative w-full select-none"
        :style="{ height: `${TIMELINE_HEIGHT}px` }"
    >
        <canvas
            ref="canvasRef"
            class="absolute inset-0 cursor-crosshair"
            @pointerdown="onPointerDown"
            @pointermove="onPointerMove"
            @pointerup="onPointerUp"
            @wheel.prevent="onWheel"
        />
    </div>
</template>
