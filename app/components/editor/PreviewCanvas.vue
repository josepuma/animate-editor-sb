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

// ─── Lifecycle ────────────────────────────────────────────────────────────────

onMounted(async () => {
    if (!containerRef.value) return
    await renderer.init(containerRef.value)
    isReady.value = true

    // Sprites may have arrived before the renderer was ready — catch up now
    if (props.sprites.length > 0) {
        await renderer.loadTextures(props.sprites, props.getFileHandle)
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
        await renderer.loadTextures(sprites, props.getFileHandle)
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
    <div ref="containerRef" class="relative w-full h-full overflow-hidden bg-black" />
</template>
