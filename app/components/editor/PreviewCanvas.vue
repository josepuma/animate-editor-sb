<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { StoryboardRenderer, OSU_WIDTH, OSU_HEIGHT, OSU_X_OFFSET } from '~/lib/engine/renderer'
import type { StoryboardSprite, TextSpriteMap } from '~/types'

// ─── Props ────────────────────────────────────────────────────────────────────

const props = defineProps<{
    sprites: StoryboardSprite[]
    currentMs: number
    getFileHandle: (path: string) => Promise<FileSystemFileHandle | null>
    /** Increment to trigger a full renderer reset (new project loaded). */
    resetKey: number
    /** Text sprite definitions — populated when scripts use text(). */
    textSpriteMap?: TextSpriteMap
}>()

// ─── State ────────────────────────────────────────────────────────────────────

const containerRef = ref<HTMLDivElement | null>(null)
const renderer = new StoryboardRenderer()
const isReady = ref(false)
const fpsVisible = ref(false)
const gridVisible = ref(false)
const isLoadingTextures = ref(false)

// ─── Cursor position in osu! storyboard coordinates ──────────────────────────

const cursorPos = ref<{ x: number; y: number; cx: number; cy: number } | null>(null)

function onMouseMove(e: MouseEvent) {
    const container = containerRef.value
    const canvas = renderer.canvas
    if (!container) return
    const canvasRect    = canvas.getBoundingClientRect()
    const containerRect = container.getBoundingClientRect()
    const px = e.clientX - canvasRect.left
    const py = e.clientY - canvasRect.top
    // Out of canvas bounds → hide
    if (px < 0 || py < 0 || px > canvasRect.width || py > canvasRect.height) {
        cursorPos.value = null
        return
    }
    // Map canvas pixels → osu! storyboard coordinates
    const sbX = Math.round((px / canvasRect.width)  * OSU_WIDTH  - OSU_X_OFFSET)
    const sbY = Math.round((py / canvasRect.height) * OSU_HEIGHT)
    // Badge position relative to the container, offset up-left from cursor
    const cx = e.clientX - containerRect.left
    const cy = e.clientY - containerRect.top
    cursorPos.value = { x: sbX, y: sbY, cx, cy }
}

function onMouseLeave() {
    cursorPos.value = null
}

async function onCanvasClick() {
    if (!cursorPos.value) return
    await navigator.clipboard.writeText(`${cursorPos.value.x}, ${cursorPos.value.y}`)
}

function toggleFps() {
    renderer.toggleFps()
    fpsVisible.value = !fpsVisible.value
}

function toggleGrid() {
    renderer.toggleGrid()
    gridVisible.value = !gridVisible.value
}

// ─── Lifecycle ────────────────────────────────────────────────────────────────

onMounted(async () => {
    if (!containerRef.value) return
    await renderer.init(containerRef.value)
    isReady.value = true

    if (props.sprites.length > 0) {
        await reloadTextures(props.sprites)
    }
})

onUnmounted(() => {
    renderer.destroy()
})

// ─── Texture reload (mutex) ───────────────────────────────────────────────────
// updateSprites() reads files from disk and takes time. If sprites change while
// a load is already in progress, we serialize: the in-flight load runs to
// completion, then immediately picks up the latest pending request.
// pendingReset ensures the renderer cache is cleared between projects even if a
// load is in flight when openProject() fires.

let textureLoading = false
let texturePending: StoryboardSprite[] | null = null
let pendingReset = false

async function reloadTextures(sprites: StoryboardSprite[]) {
    if (textureLoading) {
        texturePending = sprites  // overwrite — only the latest matters
        return
    }

    // Apply any deferred project reset before the next incremental load
    if (pendingReset) {
        pendingReset = false
        renderer.reset()
    }

    textureLoading = true
    isLoadingTextures.value = sprites.length > 0
    await renderer.updateSprites(sprites, props.getFileHandle, props.textSpriteMap ?? {})
    isLoadingTextures.value = false
    renderer.render(props.currentMs)
    textureLoading = false

    if (texturePending !== null) {
        const next = texturePending
        texturePending = null
        await reloadTextures(next)
    }
}

// ─── Watchers ─────────────────────────────────────────────────────────────────

// When resetKey increments (new project opened) clear the renderer cache.
// If a load is in flight, defer the reset until it finishes.
watch(
    () => props.resetKey,
    () => {
        if (textureLoading) {
            pendingReset = true
        } else {
            renderer.reset()
        }
    },
)

function isSameSprites(a: StoryboardSprite[], b: StoryboardSprite[]): boolean {
    if (a.length !== b.length) return false
    const setA = new Set(a.map(s => s.id))
    return b.every(s => setA.has(s.id))
}

// When sprites change (new script run / new .osb loaded) reload textures.
// If only the order changed (same IDs), use the fast synchronous reorder path.
watch(
    () => props.sprites,
    (newSprites, oldSprites) => {
        if (!isReady.value) return
        if (oldSprites && isSameSprites(newSprites, oldSprites)) {
            renderer.reorder(newSprites)
            renderer.render(props.currentMs)
            return
        }
        reloadTextures(newSprites)
    },
    { deep: false },
)

// When textSpriteMap changes, evict stale text textures and reload
// (e.g. user changed font/size in script — hash changes, old entry lingers in cache)
watch(
    () => props.textSpriteMap,
    () => {
        if (!isReady.value) return
        reloadTextures(props.sprites)
    },
    { deep: false },
)

// When audio timestamp changes, re-render
// Skip during texture load to prevent creating PixiJS sprites with Texture.EMPTY
watch(
    () => props.currentMs,
    (ms) => {
        if (!isReady.value || !props.sprites.length || textureLoading) return
        renderer.render(ms)
    },
)
</script>

<template>
    <div ref="containerRef" class="relative w-full h-full overflow-hidden bg-black" @mousemove="onMouseMove" @mouseleave="onMouseLeave" @click="onCanvasClick">
        <div class="absolute top-2 right-2 z-10 flex gap-1">
            <button
                class="px-2 py-0.5 text-xs font-mono rounded transition-colors"
                :class="gridVisible ? 'bg-white/20 text-white' : 'bg-black/40 text-white/50 hover:text-white/80'"
                @click="toggleGrid"
            >grid</button>
            <button
                class="px-2 py-0.5 text-xs font-mono rounded transition-colors"
                :class="fpsVisible ? 'bg-white/20 text-white' : 'bg-black/40 text-white/50 hover:text-white/80'"
                @click="toggleFps"
            >fps</button>
        </div>
        <div
            v-if="isLoadingTextures"
            class="absolute inset-0 flex items-center justify-center pointer-events-none"
        >
            <div class="size-8 rounded-full border-2 border-white/20 border-t-white animate-spin" />
        </div>
        <button
            v-if="cursorPos"
            class="absolute z-10 px-2 py-0.5 text-xs font-mono rounded tabular-nums transition-colors bg-black/60 text-white/80 hover:bg-white/20 hover:text-white -translate-x-full -translate-y-full pointer-events-none"
            :style="{ left: cursorPos.cx - 8 + 'px', top: cursorPos.cy - 8 + 'px' }"
        >x: {{ cursorPos.x }}, y: {{ cursorPos.y }}</button>
    </div>
</template>
