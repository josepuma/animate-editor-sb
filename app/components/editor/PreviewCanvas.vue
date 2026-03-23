<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { StoryboardRenderer } from '~/lib/engine/renderer'
import type { StoryboardSprite } from '~/types'

// ─── Props ────────────────────────────────────────────────────────────────────

const props = defineProps<{
    sprites: StoryboardSprite[]
    currentMs: number
    getFileHandle: (path: string) => Promise<FileSystemFileHandle | null>
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
        isLoadingTextures.value = true
        await renderer.loadTextures(props.sprites, props.getFileHandle)
        isLoadingTextures.value = false
        renderer.render(props.currentMs)
    }
})

onUnmounted(() => {
    renderer.destroy()
})

// ─── Watchers ─────────────────────────────────────────────────────────────────

// When sprites change (new script run / new .osb loaded) reload textures
watch(
    () => props.sprites,
    async (sprites) => {
        if (!isReady.value) return
        isLoadingTextures.value = true
        await renderer.loadTextures(sprites, props.getFileHandle)
        isLoadingTextures.value = false
        renderer.render(props.currentMs)
    },
    { deep: false },
)

// When audio timestamp changes, re-render
watch(
    () => props.currentMs,
    (ms) => {
        if (!isReady.value || !props.sprites.length) return
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
