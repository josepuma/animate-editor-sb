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
const OVERVIEW_HEIGHT = 24
const DETAIL_HEIGHT = 48
const BLOCK_RADIUS = 4
const BLOCK_PADDING_Y = 3

// ─── State ────────────────────────────────────────────────────────────────────

const wrapperRef = ref<HTMLDivElement | null>(null)
const overviewCanvasRef = ref<HTMLCanvasElement | null>(null)
const detailCanvasRef = ref<HTMLCanvasElement | null>(null)
const msPerPx = ref(DEFAULT_MS_PER_PX)
const viewportCenterMs = ref(0)
const isDragging = ref(false)
const isDraggingOverview = ref(false)
const followPlayback = ref(true)

let wrapperWidth = 0
let dpr = 1
let rafId = 0

// ─── Canvas setup ─────────────────────────────────────────────────────────────

function setupCanvases() {
    const wrapper = wrapperRef.value
    if (!wrapper) return

    dpr = window.devicePixelRatio || 1
    wrapperWidth = wrapper.clientWidth

    const oc = overviewCanvasRef.value
    if (oc) {
        oc.width = wrapperWidth * dpr
        oc.height = OVERVIEW_HEIGHT * dpr
        oc.style.width = `${wrapperWidth}px`
        oc.style.height = `${OVERVIEW_HEIGHT}px`
    }

    const dc = detailCanvasRef.value
    if (dc) {
        dc.width = wrapperWidth * dpr
        dc.height = DETAIL_HEIGHT * dpr
        dc.style.width = `${wrapperWidth}px`
        dc.style.height = `${DETAIL_HEIGHT}px`
    }
}

// ─── Overview drawing (full song) ─────────────────────────────────────────────

function drawOverview() {
    const canvas = overviewCanvasRef.value
    if (!canvas || props.durationMs <= 0) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    ctx.save()
    ctx.scale(dpr, dpr)

    const w = wrapperWidth
    const h = OVERVIEW_HEIGHT
    const dur = props.durationMs

    const msToX = (ms: number) => (ms / dur) * w

    // Background
    ctx.fillStyle = '#0a0a12'
    ctx.fillRect(0, 0, w, h)

    // Break periods (rounded blocks)
    ctx.fillStyle = 'rgba(100, 110, 160, 0.55)'
    for (const bp of props.breaks) {
        const x0 = msToX(bp.startTime)
        const x1 = msToX(bp.endTime)
        roundRect(ctx, x0, BLOCK_PADDING_Y, x1 - x0, h - BLOCK_PADDING_Y * 2, BLOCK_RADIUS)
        ctx.fill()
    }

    // Kiai sections (rounded blocks)
    ctx.fillStyle = 'rgba(255, 170, 0, 0.50)'
    for (const ks of props.kiaiSections) {
        const x0 = msToX(ks.startTime)
        const x1 = Math.min(w, msToX(ks.endTime))
        roundRect(ctx, x0, BLOCK_PADDING_Y, x1 - x0, h - BLOCK_PADDING_Y * 2, BLOCK_RADIUS)
        ctx.fill()
    }

    // BPM change markers (red lines)
    if (props.timingData) {
        ctx.strokeStyle = 'rgba(255, 100, 100, 0.4)'
        ctx.lineWidth = 1
        for (const tp of props.timingData.uninheritedPoints) {
            const x = msToX(tp.time)
            if (x < 0 || x > w) continue
            ctx.beginPath()
            ctx.moveTo(x, 0)
            ctx.lineTo(x, h)
            ctx.stroke()
        }
    }

    // Viewport indicator (shows what the detail view is looking at)
    const vpStartMs = viewportCenterMs.value - (wrapperWidth / 2) * msPerPx.value
    const vpEndMs = viewportCenterMs.value + (wrapperWidth / 2) * msPerPx.value
    const vpX0 = Math.max(0, msToX(vpStartMs))
    const vpX1 = Math.min(w, msToX(vpEndMs))

    // Dim outside viewport
    ctx.fillStyle = 'rgba(0, 0, 0, 0.4)'
    if (vpX0 > 0) ctx.fillRect(0, 0, vpX0, h)
    if (vpX1 < w) ctx.fillRect(vpX1, 0, w - vpX1, h)

    // Viewport bracket
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)'
    ctx.lineWidth = 1
    ctx.strokeRect(vpX0, 0.5, vpX1 - vpX0, h - 1)

    // Playhead
    const phX = msToX(props.currentMs)
    ctx.strokeStyle = '#a78bfa'
    ctx.lineWidth = 1.5
    ctx.beginPath()
    ctx.moveTo(phX, 0)
    ctx.lineTo(phX, h)
    ctx.stroke()

    ctx.restore()
}

// ─── Detail drawing (zoomed view) ─────────────────────────────────────────────

function drawDetail() {
    const canvas = detailCanvasRef.value
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    ctx.save()
    ctx.scale(dpr, dpr)

    const w = wrapperWidth
    const h = DETAIL_HEIGHT
    const startMs = viewportCenterMs.value - (w / 2) * msPerPx.value
    const endMs = viewportCenterMs.value + (w / 2) * msPerPx.value

    const msToX = (ms: number) => (ms - startMs) / msPerPx.value

    // 1. Background
    ctx.fillStyle = '#0f0f17'
    ctx.fillRect(0, 0, w, h)

    // 2. Break periods
    ctx.fillStyle = 'rgba(100, 110, 160, 0.45)'
    for (const bp of props.breaks) {
        if (bp.endTime < startMs || bp.startTime > endMs) continue
        const x0 = Math.max(0, msToX(bp.startTime))
        const x1 = Math.min(w, msToX(bp.endTime))
        ctx.fillRect(x0, 0, x1 - x0, h)
    }

    // 3. Kiai sections
    ctx.fillStyle = 'rgba(255, 170, 0, 0.35)'
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
        const durationX = msToX(props.durationMs)
        if (durationX < w) {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.6)'
            ctx.fillRect(Math.max(0, durationX), 0, w - durationX, h)
        }
        const zeroX = msToX(0)
        if (zeroX > 0) {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.6)'
            ctx.fillRect(0, 0, zeroX, h)
        }
    }

    // 7. Playhead
    const playheadX = msToX(props.currentMs)
    if (playheadX >= -2 && playheadX <= w + 2) {
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

        // Time badge
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
    if (followPlayback.value && !isDragging.value && !isDraggingOverview.value && props.hasAudio) {
        viewportCenterMs.value = props.currentMs
    }

    drawOverview()
    drawDetail()
    rafId = requestAnimationFrame(tick)
}

// ─── Detail interaction ───────────────────────────────────────────────────────

function detailXToMs(clientX: number): number {
    const canvas = detailCanvasRef.value
    if (!canvas) return 0
    const rect = canvas.getBoundingClientRect()
    const x = clientX - rect.left
    return viewportCenterMs.value + (x - wrapperWidth / 2) * msPerPx.value
}

function onDetailPointerDown(e: PointerEvent) {
    if (!props.hasAudio) return
    isDragging.value = true
    const ms = clampMs(detailXToMs(e.clientX))
    emit('seek', ms)
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
}

function onDetailPointerMove(e: PointerEvent) {
    if (!isDragging.value) return
    const ms = clampMs(detailXToMs(e.clientX))
    emit('seek', ms)
}

function onDetailPointerUp() {
    if (!isDragging.value) return
    isDragging.value = false
    followPlayback.value = true
}

function onDetailWheel(e: WheelEvent) {
    e.preventDefault()

    if (e.ctrlKey || e.metaKey) {
        const canvas = detailCanvasRef.value
        if (!canvas) return
        const rect = canvas.getBoundingClientRect()
        const mouseX = e.clientX - rect.left
        const mouseMs = viewportCenterMs.value + (mouseX - wrapperWidth / 2) * msPerPx.value

        const factor = e.deltaY > 0 ? 1.15 : 1 / 1.15
        msPerPx.value = Math.min(MAX_MS_PER_PX, Math.max(MIN_MS_PER_PX, msPerPx.value * factor))

        viewportCenterMs.value = mouseMs - (mouseX - wrapperWidth / 2) * msPerPx.value
        followPlayback.value = false
    } else {
        const panMs = e.deltaY * msPerPx.value * 3
        viewportCenterMs.value += panMs
        followPlayback.value = false
    }
}

// ─── Overview interaction ─────────────────────────────────────────────────────

function overviewXToMs(clientX: number): number {
    const canvas = overviewCanvasRef.value
    if (!canvas || props.durationMs <= 0) return 0
    const rect = canvas.getBoundingClientRect()
    const x = clientX - rect.left
    return (x / wrapperWidth) * props.durationMs
}

function onOverviewPointerDown(e: PointerEvent) {
    if (!props.hasAudio) return
    isDraggingOverview.value = true
    followPlayback.value = false
    const ms = clampMs(overviewXToMs(e.clientX))
    viewportCenterMs.value = ms
    emit('seek', ms)
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
}

function onOverviewPointerMove(e: PointerEvent) {
    if (!isDraggingOverview.value) return
    const ms = clampMs(overviewXToMs(e.clientX))
    viewportCenterMs.value = ms
    emit('seek', ms)
}

function onOverviewPointerUp() {
    if (!isDraggingOverview.value) return
    isDraggingOverview.value = false
    followPlayback.value = true
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
    const radius = Math.min(r, w / 2, h / 2)
    ctx.beginPath()
    ctx.moveTo(x + radius, y)
    ctx.lineTo(x + w - radius, y)
    ctx.arcTo(x + w, y, x + w, y + radius, radius)
    ctx.lineTo(x + w, y + h - radius)
    ctx.arcTo(x + w, y + h, x + w - radius, y + h, radius)
    ctx.lineTo(x + radius, y + h)
    ctx.arcTo(x, y + h, x, y + h - radius, radius)
    ctx.lineTo(x, y + radius)
    ctx.arcTo(x, y, x + radius, y, radius)
    ctx.closePath()
}

function clampMs(ms: number): number {
    return Math.max(0, Math.min(props.durationMs, ms))
}

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
    const targetMs = msPerPx * 100
    const intervals = [500, 1000, 2000, 5000, 10000, 30000, 60000]
    for (const iv of intervals) {
        if (iv >= targetMs) return iv
    }
    return 60000
}

// ─── Watchers ─────────────────────────────────────────────────────────────────

watch(
    () => props.isPlaying,
    (playing) => {
        if (playing) followPlayback.value = true
    },
)

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
    setupCanvases()
    rafId = requestAnimationFrame(tick)

    if (wrapperRef.value) {
        resizeObserver = new ResizeObserver(() => {
            setupCanvases()
            drawOverview()
            drawDetail()
        })
        resizeObserver.observe(wrapperRef.value)
    }

    viewportCenterMs.value = props.currentMs
})

onUnmounted(() => {
    cancelAnimationFrame(rafId)
    resizeObserver?.disconnect()
})
</script>

<template>
    <div ref="wrapperRef" class="w-full select-none">
        <!-- Overview: full song minimap -->
        <div class="relative" :style="{ height: `${OVERVIEW_HEIGHT}px` }">
            <canvas
                ref="overviewCanvasRef"
                class="absolute inset-0 cursor-pointer"
                @pointerdown="onOverviewPointerDown"
                @pointermove="onOverviewPointerMove"
                @pointerup="onOverviewPointerUp"
            />
        </div>
        <!-- Detail: zoomed beat view -->
        <div class="relative" :style="{ height: `${DETAIL_HEIGHT}px` }">
            <canvas
                ref="detailCanvasRef"
                class="absolute inset-0 cursor-crosshair"
                @pointerdown="onDetailPointerDown"
                @pointermove="onDetailPointerMove"
                @pointerup="onDetailPointerUp"
                @wheel.prevent="onDetailWheel"
            />
        </div>
    </div>
</template>
