<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { parseOsb } from '~/lib/parser/osb'
import type { StoryboardSprite } from '~/types'
import type { ProjectConfig } from '~/types/project'

// ─── Composables ──────────────────────────────────────────────────────────────

const fs        = useFileSystem()
const audio     = useAudio()
const scripting = useScripting()

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

sprite('sb/logo.png', Layer.Foreground, Origin.Centre)
  .fade(Easing.SineOut, beat(0), beat(2), 0, 1)
  .scale(Easing.QuadOut, beat(0), beat(2), 0.8, 1)
`
const code           = ref(DEFAULT_SCRIPT)
const selectedScript = ref<string | null>(null)
const isSaving       = ref(false)
const activeMode     = ref<'osb' | 'script'>('osb')

// ─── Derived ──────────────────────────────────────────────────────────────────

const osbFiles    = computed(() => fs.listFiles('.osb'))
const audioFiles  = computed(() => fs.listFiles('.mp3', '.ogg', '.wav'))
const tsFiles     = computed(() => fs.listFiles('.ts'))
const projectName = computed(() => fs.rootHandle.value?.name ?? null)
const hasProject  = computed(() => fs.rootHandle.value !== null)
const hasAudio    = computed(() => audio.durationMs.value > 0)

const displaySprites = computed(() =>
    activeMode.value === 'script' ? scripting.sprites.value : osbSprites.value
)

const scriptLabel = computed(() =>
    selectedScript.value
        ? selectedScript.value.split('/').pop() ?? selectedScript.value
        : 'unsaved',
)

// ─── Slider drag ──────────────────────────────────────────────────────────────

const isDragging = ref(false)
const dragMs     = ref(0)
const seekValue  = computed(() => [isDragging.value ? dragMs.value : audio.currentMs.value])

// ─── Actions ──────────────────────────────────────────────────────────────────

async function openProject() {
    loadError.value = null
    osbSprites.value = []
    selectedOsb.value = null
    selectedScript.value = null
    projectConfig.value = null
    audio.unload()
    scripting.clear()

    const ok = await fs.openProject()
    if (!ok) return

    // Load project config
    const configText = await fs.readTextFile('storybrew.json')
    if (configText) {
        try {
            const cfg = JSON.parse(configText) as ProjectConfig
            projectConfig.value = cfg
            scriptBpm.value    = cfg.bpm ?? 180
            scriptOffset.value = cfg.offset ?? 0
        } catch {
            console.warn('[index] Could not parse storybrew.json')
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

    // Auto-load first .ts script (loadScript already runs it)
    const scripts = fs.listFiles('.ts')
    if (scripts.length > 0) await loadScript(scripts[0]!.path)
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
    await scripting.run(scriptId, code.value, scriptBpm.value, scriptOffset.value)
    if (scripting.errors.value.length === 0) {
        activeMode.value = 'script'
    }
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

function onSliderPointerDown() {
    dragMs.value = audio.currentMs.value
    isDragging.value = true
}

function onSliderUpdate(val: number[]) {
    dragMs.value = val[0] ?? 0
}

function onSliderPointerUp() {
    if (!isDragging.value) return
    isDragging.value = false
    audio.seek(dragMs.value)
}

// ─── Keyboard shortcuts ───────────────────────────────────────────────────────

const SEEK_STEP_MS = 5000

function onKeyDown(e: KeyboardEvent) {
    const tag = (e.target as HTMLElement).tagName
    if (tag === 'INPUT' || tag === 'TEXTAREA') return
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
        audio.seek(audio.currentMs.value + SEEK_STEP_MS)
    } else if (e.code === 'ArrowLeft') {
        e.preventDefault()
        audio.seek(audio.currentMs.value - SEEK_STEP_MS)
    }
}

onMounted(() => {
    window.addEventListener('keydown', onKeyDown)
    window.addEventListener('pointerup', onSliderPointerUp)
})
onUnmounted(() => {
    window.removeEventListener('keydown', onKeyDown)
    window.removeEventListener('pointerup', onSliderPointerUp)
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
                MenubarTrigger.font-semibold.text-sm.px-2 storybrew web

            MenubarMenu
                MenubarTrigger.text-sm.px-2 File
                MenubarContent
                    MenubarItem(@click="openProject")
                        | Open Project
                        MenubarShortcut Ctrl+O
                    MenubarSeparator
                    MenubarItem(:disabled="!hasProject" @click="fs.refresh()")
                        | Refresh Files

            MenubarMenu
                MenubarTrigger.text-sm.px-2 Script
                MenubarContent
                    MenubarItem(:disabled="!hasProject" @click="newScriptDialogOpen = true")
                        | New Script
                    MenubarSeparator
                    MenubarItem(:disabled="!hasProject || !selectedScript || isSaving" @click="saveScript")
                        | Save
                        MenubarShortcut Ctrl+S
                    MenubarItem(:disabled="!hasProject || scripting.isRunning.value" @click="runScript")
                        | Run
                        MenubarShortcut Ctrl+↵

            MenubarMenu
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
                    p.px-3.py-1.text-xs.font-semibold.text-muted-foreground.uppercase.tracking-wider Scripts
                    template(v-if="tsFiles.length")
                        button(
                            v-for="f in tsFiles"
                            :key="f.path"
                            class="w-full text-left px-3 py-1.5 text-xs truncate transition-colors hover:bg-accent hover:text-accent-foreground"
                            :class="selectedScript === f.path ? 'bg-accent text-accent-foreground' : ''"
                            @click="loadScript(f.path)"
                        ) {{ f.name }}
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
                    )
                    .absolute.inset-0.flex.items-center.justify-center.text-white.text-sm(
                        class="bg-black/60"
                        v-if="isLoadingOsb"
                    ) Loading storyboard…
                    .absolute.inset-0.flex.items-center.justify-center.p-6(v-if="loadError")
                        pre.border.border-destructive.text-destructive.text-xs.rounded.p-4.max-w-md.overflow-auto(
                            class="bg-destructive/10"
                        ) {{ loadError }}

                //- Audio controls
                .shrink-0.border-t.border-border.px-4.py-2.flex.items-center.gap-3
                    Button(
                        size="sm"
                        variant="ghost"
                        class="size-8 p-0"
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
                        @pointerdown="onSliderPointerDown"
                        @update:model-value="onSliderUpdate"
                    )

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
