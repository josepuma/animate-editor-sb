<script setup lang="ts">
import { ref, computed, onUnmounted } from 'vue'
import { parseOsb } from '~/lib/parser/osb'
import type { StoryboardSprite } from '~/types'

// ─── Composables ──────────────────────────────────────────────────────────────

const fs = useFileSystem()
const audio = useAudio()

// ─── State ────────────────────────────────────────────────────────────────────

const sprites = ref<StoryboardSprite[]>([])
const selectedOsb = ref<string | null>(null)
const loadError = ref<string | null>(null)
const isLoadingOsb = ref(false)

// ─── Derived ──────────────────────────────────────────────────────────────────

const osbFiles = computed(() => fs.listFiles('.osb'))
const audioFiles = computed(() => fs.listFiles('.mp3', '.ogg', '.wav'))
const projectName = computed(() => fs.rootHandle.value?.name ?? null)
const hasProject = computed(() => fs.rootHandle.value !== null)
const hasAudio = computed(() => audio.durationMs.value > 0)
const seekValue = computed(() => [audio.currentMs.value])

// ─── Actions ──────────────────────────────────────────────────────────────────

async function openProject() {
    loadError.value = null
    sprites.value = []
    selectedOsb.value = null

    const ok = await fs.openProject()
    if (!ok) return

    const osbs = fs.listFiles('.osb')
    if (osbs.length > 0) await loadOsb(osbs[0]!.path)

    const audios = fs.listFiles('.mp3', '.ogg', '.wav')
    if (audios.length > 0) {
        const handle = await fs.getFileHandle(audios[0]!.path)
        if (handle) await audio.loadFromHandle(handle)
    }
}

async function loadOsb(path: string) {
    isLoadingOsb.value = true
    loadError.value = null
    try {
        const text = await fs.readTextFile(path)
        if (!text) throw new Error(`Could not read: ${path}`)
        sprites.value = parseOsb(text).sprites
        selectedOsb.value = path
    } catch (err) {
        loadError.value = err instanceof Error ? err.message : String(err)
    } finally {
        isLoadingOsb.value = false
    }
}

async function selectAudio(path: string) {
    const handle = await fs.getFileHandle(path)
    if (handle) await audio.loadFromHandle(handle)
}

function formatMs(ms: number): string {
    const s = Math.floor(ms / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

function onSeek(val: number[]) {
    audio.seek(val[0] ?? 0)
}

onUnmounted(() => audio.destroy())
</script>

<template lang="pug">
div.flex.flex-col.h-screen.bg-background.text-foreground.overflow-hidden

    //- Toolbar
    header.flex.items-center.gap-3.px-4.h-12.border-b.border-border.shrink-0
        span.font-semibold.text-sm storybrew-web
        Separator(orientation="vertical" class="h-5")
        Button(size="sm" variant="outline" @click="openProject") Open Project
        span.text-muted-foreground.text-xs(v-if="projectName") {{ projectName }}
        .ml-auto.flex.items-center.gap-3.text-xs.text-muted-foreground
            span(v-if="sprites.length") {{ sprites.length }} sprites
            span.max-w-48.truncate(v-if="selectedOsb") {{ selectedOsb }}

    //- Body
    .flex.flex-1.min-h-0

        //- Sidebar
        aside.w-52.shrink-0.border-r.border-border.flex.flex-col.overflow-hidden(v-if="hasProject")
            ScrollArea.flex-1
                .py-2
                    p.px-3.py-1.text-xs.font-semibold.text-muted-foreground.uppercase.tracking-wider Storyboard
                    template(v-if="osbFiles.length")
                        button(
                            v-for="f in osbFiles"
                            :key="f.path"
                            class="w-full text-left px-3 py-1.5 text-xs truncate transition-colors hover:bg-accent hover:text-accent-foreground"
                            :class="selectedOsb === f.path ? 'bg-accent text-accent-foreground' : ''"
                            @click="loadOsb(f.path)"
                        ) {{ f.name }}
                    p.px-3.py-1.text-xs.text-muted-foreground(v-else) No .osb files
                    Separator.my-2
                    p.px-3.py-1.text-xs.font-semibold.text-muted-foreground.uppercase.tracking-wider Audio
                    template(v-if="audioFiles.length")
                        button(
                            v-for="f in audioFiles"
                            :key="f.path"
                            class="w-full text-left px-3 py-1.5 text-xs truncate transition-colors hover:bg-accent hover:text-accent-foreground"
                            @click="selectAudio(f.path)"
                        ) {{ f.name }}
                    p.px-3.py-1.text-xs.text-muted-foreground(v-else) No audio files

        //- Main canvas area
        main.flex-1.flex.flex-col.min-w-0.min-h-0

            //- Empty state
            .flex-1.flex.flex-col.items-center.justify-center.gap-4.text-muted-foreground(v-if="!hasProject")
                span.text-5xl.select-none 🎬
                p.text-sm Open an osu! project folder to get started
                Button(@click="openProject") Open Project

            template(v-else)
                //- Canvas
                .flex-1.min-h-0.relative.bg-black
                    EditorPreviewCanvas(
                        :sprites="sprites"
                        :current-ms="audio.currentMs.value"
                        :get-file-handle="fs.getFileHandle"
                    )
                    div(
                        v-if="isLoadingOsb"
                        class="absolute inset-0 flex items-center justify-center bg-black/60 text-white text-sm"
                    )
                        | Loading storyboard…
                    div(
                        v-if="loadError"
                        class="absolute inset-0 flex items-center justify-center p-6"
                    )
                        pre(class="bg-destructive/10 border border-destructive text-destructive text-xs rounded p-4 max-w-md overflow-auto") {{ loadError }}

                //- Audio controls
                .shrink-0.border-t.border-border.px-4.py-2.flex.items-center.gap-3
                    Button.size-8.p-0(
                        size="sm"
                        variant="ghost"
                        :disabled="!hasAudio"
                        @click="audio.isPlaying.value ? audio.pause() : audio.play()"
                    )
                        Icon(:name="audio.isPlaying.value ? 'lucide:pause' : 'lucide:play'" size="14")
                    span.text-xs.tabular-nums.text-muted-foreground.w-24.shrink-0
                        | {{ formatMs(audio.currentMs.value) }} / {{ formatMs(audio.durationMs.value) }}
                    Slider.flex-1(
                        :min="0"
                        :max="audio.durationMs.value"
                        :step="1"
                        :model-value="seekValue"
                        :disabled="!hasAudio"
                        @update:model-value="onSeek"
                    )
</template>
