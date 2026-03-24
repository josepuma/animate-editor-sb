<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { StoryboardRenderer } from '~/lib/engine/renderer'
import type { StoryboardSprite } from '~/types'

// ─── Props ────────────────────────────────────────────────────────────────────

const props = defineProps<{
    sprites: StoryboardSprite[]
    currentMs: number
    getFileHandle: (path: string) => Promise<FileSystemFileHandle | null>
    /** Increment to trigger a full renderer reset (new project loaded). */
    resetKey: number
}>()

// ─── State ────────────────────────────────────────────────────────────────────

const containerRef = ref<HTMLDivElement | null>(null)
const renderer = new StoryboardRenderer()
const isReady = ref(false)
const fpsVisible = ref(false)
const isLoadingTextures = ref(false)

function toggleFps() {
    renderer.toggleFps()
    fpsVisible.value = !fpsVisible.value
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
    await renderer.updateSprites(sprites, props.getFileHandle)
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

// When sprites change (new script run / new .osb loaded) reload textures
watch(
    () => props.sprites,
    (sprites) => {
        if (!isReady.value) return
        reloadTextures(sprites)
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
    <div ref="containerRef" class="relative w-full h-full overflow-hidden bg-black">
        <button
            class="absolute top-2 right-2 z-10 px-2 py-0.5 text-xs font-mono rounded transition-colors"
            :class="fpsVisible ? 'bg-white/20 text-white' : 'bg-black/40 text-white/50 hover:text-white/80'"
            @click="toggleFps"
        >fps</button>
        <div
            v-if="isLoadingTextures"
            class="absolute inset-0 flex items-center justify-center pointer-events-none"
        >
            <div class="size-8 rounded-full border-2 border-white/20 border-t-white animate-spin" />
        </div>
    </div>
</template>
