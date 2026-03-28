<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { parseOsb } from '~/lib/parser/osb'
import type { StoryboardSprite } from '~/types'
import type { ProjectConfig } from '~/types/project'

// ─── Composables ──────────────────────────────────────────────────────────────

const fs        = useFileSystem()
const audio     = useAudio()
const scripting = useScripting()
const timing    = useTiming()

// ─── Project config ───────────────────────────────────────────────────────────

const projectConfig  = ref<ProjectConfig | null>(null)
const scriptBpm      = ref(180)
const scriptOffset   = ref(0)

// ─── OSB state ────────────────────────────────────────────────────────────────

const osbSprites   = ref<StoryboardSprite[]>([])
const selectedOsb  = ref<string | null>(null)
const loadError    = ref<string | null>(null)
const isLoadingOsb = ref(false)

// ─── Dialog state ─────────────────────────────────────────────────────────────

const newScriptDialogOpen = ref(false)
const newScriptName       = ref('scripts/main.ts')

// ─── Script editor state ──────────────────────────────────────────────────────

const DEFAULT_SCRIPT = `// Storyboard script
// Globals: sprite(), beat(), bpm, offset, Easing, Layer, Origin

/*sprite('sb/logo.png', Layer.Foreground, Origin.Centre)
  .fade(Easing.SineOut, beat(0), beat(2), 0, 1)
  .scale(Easing.QuadOut, beat(0), beat(2), 0.8, 1)*/
`
const code             = ref(DEFAULT_SCRIPT)
const selectedScript   = ref<string | null>(null)
const isSaving         = ref(false)
const activeMode       = ref<'osb' | 'script'>('osb')
const previewResetKey  = ref(0)

// ─── Script render order ──────────────────────────────────────────────────────
// Paths in bottom-to-top render order: first = rendered below, last = rendered on top.

const scriptOrder = ref<string[]>([])

// Keep scriptOrder in sync when scripts are added/removed.
// IMPORTANT: filter based on files on DISK (tsFiles), not on spritesByScript.
// spritesByScript is populated incrementally as scripts finish running — using it
// to filter would drop scripts that are still compiling during openProject().
watch(
    () => scripting.spritesByScript.value,
    (map) => {
        const present  = new Set(Object.keys(map))
        const onDisk   = new Set(fs.listFiles('.ts').map(f => f.path))
        // Keep entries that still exist on disk (preserves order of scripts not yet run)
        const filtered = scriptOrder.value.filter(p => onDisk.has(p))
        // Append scripts that ran but aren't in the order yet (new scripts)
        const newPaths = [...present].filter(p => !filtered.includes(p))
        if (filtered.length !== scriptOrder.value.length || newPaths.length > 0) {
            scriptOrder.value = [...filtered, ...newPaths]
            // Persist new scripts into config immediately so their position survives reload
            if (newPaths.length > 0) saveProjectConfig()
        }
    },
    { deep: false },
)

// ─── Derived ──────────────────────────────────────────────────────────────────

const osbFiles    = computed(() => fs.listFiles('.osb'))
const audioFiles  = computed(() => fs.listFiles('.mp3', '.ogg', '.wav'))
const tsFiles     = computed(() => fs.listFiles('.ts'))
const projectName = computed(() => fs.rootHandle.value?.name ?? null)
const hasProject  = computed(() => fs.rootHandle.value !== null)
const hasAudio    = computed(() => audio.durationMs.value > 0)

const displaySprites = computed(() => {
    if (activeMode.value !== 'script') return osbSprites.value
    const map = scripting.spritesByScript.value
    // Flatten in scriptOrder: first = rendered below, last = rendered on top
    const ordered = scriptOrder.value.flatMap(p => map[p] ?? [])
    // Any scripts not in order yet (shouldn't happen, but safety net)
    const unordered = Object.entries(map)
        .filter(([p]) => !scriptOrder.value.includes(p))
        .flatMap(([, sprites]) => sprites)
    return [...ordered, ...unordered]
})

const scriptLabel = computed(() =>
    selectedScript.value
        ? selectedScript.value.split('/').pop() ?? selectedScript.value
        : 'unsaved',
)

// ─── Image dimensions cache ──────────────────────────────────────────────────
// Pre-scanned on project open so scripts can access sprite.width / sprite.height.

const imageDims = ref<Record<string, { width: number; height: number }>>({})

const IMAGE_EXTS = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp']

async function scanImageDimensions() {
    const images = fs.listFiles(...IMAGE_EXTS)
    const dims: Record<string, { width: number; height: number }> = {}
    await Promise.all(
        images.map(async (img) => {
            try {
                const handle = await fs.getFileHandle(img.path)
                if (!handle) return
                const file = await handle.getFile()
                const bitmap = await createImageBitmap(file)
                dims[img.path] = { width: bitmap.width, height: bitmap.height }
                bitmap.close()
            } catch { /* skip unreadable images */ }
        }),
    )
    imageDims.value = dims
}

// ─── Beat divisor options ────────────────────────────────────────────────────

const DIVISOR_OPTIONS = [1, 2, 4, 8, 16] as const

// ─── Actions ──────────────────────────────────────────────────────────────────

async function openProject() {
    loadError.value = null
    osbSprites.value = []
    selectedOsb.value = null
    selectedScript.value = null
    projectConfig.value = null
    scriptOrder.value = []
    audio.unload()
    scripting.clear()
    previewResetKey.value++  // tell PreviewCanvas to reset the renderer cache

    const ok = await fs.openProject()
    if (!ok) return

    // Load project config
    const configText = await fs.readTextFile('animate.json')
    if (configText) {
        try {
            const cfg = JSON.parse(configText) as ProjectConfig
            projectConfig.value = cfg
            scriptBpm.value    = cfg.bpm ?? 180
            scriptOffset.value = cfg.offset ?? 0
            // Migrate old paths that included the root folder name prefix
            const rootName = fs.rootHandle.value?.name ?? ''
            const rawOrder = cfg.scriptOrder ?? []
            const migrated = rootName
                ? rawOrder.map(p => p.startsWith(rootName + '/') ? p.slice(rootName.length + 1) : p)
                : rawOrder
            scriptOrder.value = [...new Set(migrated)]
        } catch {
            console.warn('[index] Could not parse animate.json')
        }
    }

    // Auto-load first .osb
    const osbs = fs.listFiles('.osb')
    if (osbs.length > 0) await loadOsb(osbs[0]!.path)

    // Auto-load first audio
    const audios = fs.listFiles('.mp3', '.ogg', '.wav')
    if (audios.length > 0) {
        const handle = await fs.getFileHandle(audios[0]!.path)
        if (handle) await audio.loadFromHandle(handle)
    }

    // Auto-detect timing from .osu files
    timing.clear()
    const osuFiles = fs.listFiles('.osu')
    if (osuFiles.length > 0) {
        const osuContent = await fs.readTextFile(osuFiles[0]!.path)
        if (osuContent) {
            timing.loadFromOsu(osuContent)
            const bpm = timing.primaryBpm.value
            if (bpm !== null) {
                scriptBpm.value = Math.round(bpm)
                const firstPoint = timing.timingData.value?.uninheritedPoints[0]
                if (firstPoint) scriptOffset.value = Math.round(firstPoint.time)
            }
        }
    }

    // Pre-scan image dimensions so scripts can access sprite.width / sprite.height
    await scanImageDimensions()

    // Run ALL .ts scripts concurrently — per-script runSeqMap means they
    // don't cancel each other. The renderer updates incrementally as each finishes.
    const scripts = fs.listFiles('.ts')
    if (scripts.length > 0) {
        activeMode.value = 'script'
        await Promise.all(
            scripts.map(async (s) => {
                const text = await fs.readTextFile(s.path)
                if (text !== null) {
                    await scripting.run(s.path, text, scriptBpm.value, scriptOffset.value, JSON.parse(JSON.stringify(imageDims.value)))
                }
            }),
        )
    }
}

async function loadOsb(path: string) {
    isLoadingOsb.value = true
    loadError.value = null
    try {
        const text = await fs.readTextFile(path)
        if (!text) throw new Error(`Could not read: ${path}`)
        osbSprites.value = parseOsb(text).sprites
        selectedOsb.value = path
        activeMode.value = 'osb'
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

async function loadAudioFile() {
    if (!fs.rootHandle.value) return
    try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const [sourceHandle] = await (window as any).showOpenFilePicker({
            types: [{ description: 'Audio', accept: { 'audio/*': ['.mp3', '.ogg', '.wav'] } }],
            multiple: false,
        }) as [FileSystemFileHandle]

        // Copy the selected file into the project root so it becomes a project asset
        const sourceFile  = await sourceHandle.getFile()
        const destHandle  = await fs.rootHandle.value.getFileHandle(sourceFile.name, { create: true })
        const writable    = await destHandle.createWritable()
        await writable.write(await sourceFile.arrayBuffer())
        await writable.close()

        // Refresh the sidebar so the file appears, then load it
        await fs.refresh()
        await audio.loadFromHandle(destHandle)
    } catch (err) {
        if ((err as DOMException).name !== 'AbortError') console.error(err)
    }
}

async function createNewScript() {
    const path = newScriptName.value.trim()
    if (!path) return
    const existing = await fs.readTextFile(path)
    if (existing === null) {
        await fs.writeTextFile(path, DEFAULT_SCRIPT)
    }
    await loadScript(path)
    newScriptDialogOpen.value = false
    newScriptName.value = 'scripts/main.ts'
}

/**
 * Opens a script for editing without re-running it.
 * Scripts are already running from openProject(); re-running on every click
 * would cause unnecessary preview reloads.
 */
async function openScript(path: string) {
    const text = await fs.readTextFile(path)
    if (text === null) return
    code.value = text
    selectedScript.value = path
}

/**
 * Opens a script AND runs it immediately.
 * Used only when creating a new script that has never run.
 */
async function loadScript(path: string) {
    const text = await fs.readTextFile(path)
    if (text === null) return
    code.value = text
    selectedScript.value = path
    await runScript()
}

async function saveScript() {
    if (!hasProject.value || isSaving.value) return
    isSaving.value = true
    const path = selectedScript.value ?? 'scripts/main.ts'
    const ok = await fs.writeTextFile(path, code.value)
    if (ok) {
        selectedScript.value = path
        await runScript()
    }
    isSaving.value = false
}

async function runScript() {
    const scriptId = selectedScript.value ?? 'default'
    await scripting.run(scriptId, code.value, scriptBpm.value, scriptOffset.value, JSON.parse(JSON.stringify(imageDims.value)))
    if (scripting.errors.value.length === 0) {
        activeMode.value = 'script'
    }
}

// ─── Script order ─────────────────────────────────────────────────────────────

async function saveProjectConfig() {
    if (!hasProject.value) return
    const cfg = { ...(projectConfig.value ?? {}), scriptOrder: scriptOrder.value }
    await fs.writeTextFile('animate.json', JSON.stringify(cfg, null, 2))
}

function moveScript(path: string, direction: -1 | 1) {
    const order = [...scriptOrder.value]
    const idx = order.indexOf(path)
    if (idx === -1) return
    const target = idx + direction
    if (target < 0 || target >= order.length) return
    ;[order[idx], order[target]] = [order[target]!, order[idx]!]
    scriptOrder.value = order
    saveProjectConfig()
}

// ─── Input handlers ───────────────────────────────────────────────────────────

function onBpmChange(e: Event) {
    scriptBpm.value = Number((e.target as HTMLInputElement).value)
}

function onOffsetChange(e: Event) {
    scriptOffset.value = Number((e.target as HTMLInputElement).value)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatMs(ms: number): string {
    const s = Math.floor(ms / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

// ─── Keyboard shortcuts ───────────────────────────────────────────────────────

const SEEK_STEP_MS = 5000

function onKeyDown(e: KeyboardEvent) {
    const tag = (e.target as HTMLElement).tagName
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
    if ((e.target as HTMLElement).closest?.('.monaco-editor')) return

    if (e.metaKey || e.ctrlKey) {
        if (e.code === 'KeyS') { e.preventDefault(); saveScript(); return }
        if (e.code === 'KeyO') { e.preventDefault(); openProject(); return }
        if (e.code === 'Enter') { e.preventDefault(); runScript(); return }
    }

    if (e.code === 'Space') {
        e.preventDefault()
        audio.isPlaying.value ? audio.pause() : audio.play()
    } else if (e.code === 'ArrowRight') {
        e.preventDefault()
        if (timing.hasTimingData.value) {
            audio.seek(timing.nextBeat(audio.currentMs.value))
        } else {
            audio.seek(audio.currentMs.value + SEEK_STEP_MS)
        }
    } else if (e.code === 'ArrowLeft') {
        e.preventDefault()
        if (timing.hasTimingData.value) {
            audio.seek(timing.prevBeat(audio.currentMs.value))
        } else {
            audio.seek(audio.currentMs.value - SEEK_STEP_MS)
        }
    }
}

function onTimelineSeek(ms: number) {
    audio.seek(ms)
}

function onDivisorChange(e: Event) {
    timing.beatDivisor.value = Number((e.target as HTMLSelectElement).value)
}

onMounted(() => {
    window.addEventListener('keydown', onKeyDown)
})
onUnmounted(() => {
    window.removeEventListener('keydown', onKeyDown)
    audio.destroy()
    scripting.destroy()
})
</script>

<template lang="pug">
div.flex.flex-col.h-screen.bg-background.text-foreground.overflow-hidden

    //- ── Menubar ──────────────────────────────────────────────────────────────
    header.flex.items-center.h-9.border-b.border-border.shrink-0

        Menubar.border-0.rounded-none.shadow-none.h-full.px-2.gap-0(class="bg-transparent")

            MenubarMenu
                MenubarTrigger.font-semibold.text-sm.px-2 anedir

            MenubarMenu
                MenubarTrigger.text-sm.px-2 File
                MenubarContent
                    MenubarItem(@click="openProject")
                        | Open Project
                        MenubarShortcut Ctrl+O
                    //-MenubarSeparator
                    //-MenubarItem(:disabled="!hasProject" @click="fs.refresh()")
                        | Refresh Files

            MenubarMenu
                MenubarTrigger.text-sm.px-2 Script
                MenubarContent
                    MenubarItem(:disabled="!hasProject" @click="newScriptDialogOpen = true")
                        | New Script

            //-MenubarMenu
                MenubarTrigger.text-sm.px-2 Audio
                MenubarContent
                    MenubarItem(:disabled="!hasProject" @click="loadAudioFile") Load Audio File…

        .ml-auto.flex.items-center.gap-2.pr-3.text-xs.text-muted-foreground
            template(v-if="projectName")
                Icon(name="lucide:folder-open" size="12")
                span.max-w-32.truncate {{ projectName }}
            template(v-if="activeMode === 'script' && scripting.sprites.value.length")
                Separator(orientation="vertical" class="h-3")
                span {{ scripting.sprites.value.length }} sprites
            template(v-else-if="activeMode === 'osb' && osbSprites.length")
                Separator(orientation="vertical" class="h-3")
                span {{ osbSprites.length }} sprites

    //- ── Body ─────────────────────────────────────────────────────────────────
    .flex.flex-1.min-h-0

        //- ── Sidebar ──────────────────────────────────────────────────────────
        aside.w-52.shrink-0.border-r.border-border.flex.flex-col.overflow-hidden(v-if="hasProject")
            ScrollArea.flex-1
                .py-2

                    //- Scripts
                    .flex.items-center.px-3.py-1
                        span.text-xs.font-semibold.text-muted-foreground.uppercase.tracking-wider.flex-1 Scripts
                        span.text-xs.text-muted-foreground(class="opacity-50" title="Render order: top = below, bottom = on top") ↑↓
                    template(v-if="tsFiles.length")
                        //- Render in scriptOrder (unknown paths appended at end)
                        .flex.items-center.group(
                            v-for="path in [...scriptOrder.filter(p => tsFiles.some(f => f.path === p)), ...tsFiles.filter(f => !scriptOrder.includes(f.path)).map(f => f.path)]"
                            :key="path"
                        )
                            button(
                                class="flex-1 min-w-0 text-left pl-3 pr-1 py-1.5 text-xs truncate transition-colors hover:bg-accent hover:text-accent-foreground"
                                :class="selectedScript === path ? 'bg-accent text-accent-foreground' : ''"
                                @click="openScript(path)"
                            ) {{ path.split('/').pop() }}
                            .flex.shrink-0.opacity-0.group-hover(class="group-hover:opacity-100")
                                button(
                                    class="px-0.5 py-1 text-muted-foreground hover:text-foreground disabled:opacity-20"
                                    :disabled="scriptOrder.indexOf(path) <= 0"
                                    @click.stop="moveScript(path, -1)"
                                    title="Move up (render below)"
                                )
                                    Icon(name="lucide:chevron-up" size="12")
                                button(
                                    class="px-0.5 py-1 text-muted-foreground hover:text-foreground disabled:opacity-20"
                                    :disabled="scriptOrder.indexOf(path) >= scriptOrder.length - 1"
                                    @click.stop="moveScript(path, 1)"
                                    title="Move down (render on top)"
                                )
                                    Icon(name="lucide:chevron-down" size="12")
                    p.px-3.py-1.text-xs.text-muted-foreground(v-else) No .ts files
                    Separator.my-2

                    //- Storyboard
                    p.px-3.py-1.text-xs.font-semibold.text-muted-foreground.uppercase.tracking-wider Storyboard
                    template(v-if="osbFiles.length")
                        button(
                            v-for="f in osbFiles"
                            :key="f.path"
                            class="w-full text-left px-3 py-1.5 text-xs truncate transition-colors hover:bg-accent hover:text-accent-foreground"
                            :class="selectedOsb === f.path && activeMode === 'osb' ? 'bg-accent text-accent-foreground' : ''"
                            @click="loadOsb(f.path)"
                        ) {{ f.name }}
                    p.px-3.py-1.text-xs.text-muted-foreground(v-else) No .osb files
                    Separator.my-2

                    //- Audio
                    p.px-3.py-1.text-xs.font-semibold.text-muted-foreground.uppercase.tracking-wider Audio
                    template(v-if="audioFiles.length")
                        button(
                            v-for="f in audioFiles"
                            :key="f.path"
                            class="w-full text-left px-3 py-1.5 text-xs truncate transition-colors hover:bg-accent hover:text-accent-foreground"
                            @click="selectAudio(f.path)"
                        ) {{ f.name }}
                    p.px-3.py-1.text-xs.text-muted-foreground(v-else) No audio files

        //- ── Center: preview + audio ──────────────────────────────────────────
        .flex-1.flex.flex-col.min-h-0.min-w-0

            //- Empty state
            .flex-1.flex.flex-col.items-center.justify-center.gap-4.text-muted-foreground(v-if="!hasProject")
                p.text-sm Open an osu! project folder to get started
                Button(@click="openProject") Open Project

            template(v-else)
                //- Canvas
                .flex-1.min-h-0.relative.bg-black
                    EditorPreviewCanvas(
                        :sprites="displaySprites"
                        :current-ms="audio.currentMs.value"
                        :get-file-handle="fs.getFileHandle"
                        :reset-key="previewResetKey"
                    )
                    .absolute.inset-0.flex.items-center.justify-center.text-white.text-sm(
                        class="bg-black/60"
                        v-if="isLoadingOsb"
                    ) Loading storyboard…
                    .absolute.inset-0.flex.items-center.justify-center.p-6(v-if="loadError")
                        pre.border.border-destructive.text-destructive.text-xs.rounded.p-4.max-w-md.overflow-auto(
                            class="bg-destructive/10"
                        ) {{ loadError }}

                //- Timeline + Audio controls
                .shrink-0.border-t.border-border.flex.flex-col
                    EditorTimeline(
                        :current-ms="audio.currentMs.value"
                        :duration-ms="audio.durationMs.value"
                        :has-audio="hasAudio"
                        :is-playing="audio.isPlaying.value"
                        :timing-data="timing.timingData.value"
                        :beat-divisor="timing.beatDivisor.value"
                        :get-beat-lines="timing.getBeatLines"
                        :kiai-sections="timing.timingData.value?.kiaiSections ?? []"
                        :breaks="timing.timingData.value?.breaks ?? []"
                        @seek="onTimelineSeek"
                    )
                    //- Transport bar
                    .flex.items-center.gap-2.px-3.h-8.border-t.border-border
                        Button(
                            size="sm"
                            variant="ghost"
                            class="size-7 p-0"
                            :disabled="!hasAudio"
                            @click="audio.isPlaying.value ? audio.pause() : audio.play()"
                        )
                            Icon(:name="audio.isPlaying.value ? 'lucide:pause' : 'lucide:play'" size="13")
                        span.text-xs.tabular-nums.text-muted-foreground.shrink-0
                            | {{ formatMs(audio.currentMs.value) }} / {{ formatMs(audio.durationMs.value) }}
                        .flex-1
                        //- Beat divisor selector
                        .flex.items-center.gap-1.text-xs.text-muted-foreground(v-if="timing.hasTimingData.value")
                            span.shrink-0 1/
                            select.bg-transparent.border.border-border.rounded.px-1.text-foreground.text-xs(
                                class="py-0.5 focus:outline-none focus:ring-1 focus:ring-ring"
                                :value="timing.beatDivisor.value"
                                @change="onDivisorChange"
                            )
                                option(v-for="d in DIVISOR_OPTIONS" :key="d" :value="d") {{ d }}
                        //- BPM display
                        span.text-xs.tabular-nums.text-muted-foreground.shrink-0(v-if="timing.primaryBpm.value")
                            | {{ Math.round(timing.primaryBpm.value) }} BPM

        //- ── Right: script editor — visible only when a script is selected ──────
        .flex.flex-col.border-l.border-border.shrink-0(v-if="selectedScript !== null" class="w-2/5 min-w-64 max-w-2xl")

            //- Editor toolbar
            .flex.items-center.gap-1.px-2.h-9.border-b.border-border.shrink-0.text-xs

                span.font-mono.text-muted-foreground.truncate.max-w-28 {{ scriptLabel }}
                Separator(orientation="vertical" class="h-4 mx-1")

                .flex.items-center.gap-1.text-muted-foreground
                    span BPM
                    input.w-14.bg-transparent.border.border-border.rounded.px-1.text-foreground(
                        class="py-0.5 focus:outline-none focus:ring-1 focus:ring-ring"
                        type="number"
                        :value="scriptBpm"
                        min="1"
                        max="999"
                        @change="onBpmChange"
                    )
                    span ms
                    input.w-16.bg-transparent.border.border-border.rounded.px-1.text-foreground(
                        class="py-0.5 focus:outline-none focus:ring-1 focus:ring-ring"
                        type="number"
                        :value="scriptOffset"
                        @change="onOffsetChange"
                    )

                .flex-1

                Button(
                    size="sm"
                    variant="ghost"
                    class="h-6 px-2 text-xs"
                    :disabled="isSaving || scripting.isRunning.value"
                    title="Save (Ctrl+S)"
                    @click="saveScript"
                )
                    Icon.mr-1(v-if="isSaving || scripting.isRunning.value" name="lucide:loader-circle" size="12" class="animate-spin")
                    Icon.mr-1(v-else name="lucide:save" size="12")
                    | Save

                Button(
                    size="sm"
                    variant="ghost"
                    class="size-6 p-0 ml-1"
                    title="Close editor"
                    @click="selectedScript = null"
                )
                    Icon(name="lucide:x" size="12")

            //- Monaco editor
            .flex-1.min-h-0
                EditorMonacoEditor(v-model="code")

            //- Script errors
            .shrink-0.border-t.border-border.max-h-40.overflow-auto(
                v-if="scripting.errors.value.length"
            )
                .px-3.py-2.flex.items-center.gap-2.text-xs.font-medium.text-destructive
                    Icon(name="lucide:circle-x" size="12")
                    | {{ scripting.errors.value.length }} error{{ scripting.errors.value.length > 1 ? 's' : '' }}
                .px-3.pb-2.flex.flex-col.gap-1
                    .text-xs.font-mono(
                        class="text-destructive/80"
                        v-for="(err, i) in scripting.errors.value"
                        :key="i"
                    )
                        span.opacity-60.mr-1 [{{ err.phase }}]
                        | {{ err.message }}

    //- ── New Script Dialog ────────────────────────────────────────────────────
    Dialog(v-model:open="newScriptDialogOpen")
        DialogContent(class="sm:max-w-md")
            DialogHeader
                DialogTitle New Script
                DialogDescription
                    | Enter the path for the new script file inside the project folder.
            .grid.gap-3.py-2
                label.text-sm.font-medium(for="new-script-name") File path
                Input#new-script-name(
                    v-model="newScriptName"
                    placeholder="scripts/main.ts"
                    @keydown.enter="createNewScript"
                )
            DialogFooter
                Button(variant="outline" @click="newScriptDialogOpen = false") Cancel
                Button(@click="createNewScript") Create
</template>
