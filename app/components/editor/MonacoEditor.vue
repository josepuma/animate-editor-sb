<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'

// ─── Props / emits ────────────────────────────────────────────────────────────

const props = withDefaults(defineProps<{
    modelValue: string
    readonly?: boolean
}>(), {
    readonly: false,
})

const emit = defineEmits<{
    'update:modelValue': [value: string]
}>()

// ─── Refs ─────────────────────────────────────────────────────────────────────

const containerRef = ref<HTMLDivElement | null>(null)
let editor: import('monaco-editor').editor.IStandaloneCodeEditor | null = null
let suppressNextChange = false
let debounceTimer: ReturnType<typeof setTimeout> | null = null

// ─── Scripting API type definitions ──────────────────────────────────────────
// Injected as an ambient .d.ts so the user gets autocomplete for the
// globals available in every storyboard script (sprite, beat, Easing, …).

const SCRIPTING_TYPES = `
declare enum Easing {
  Linear            = 0,
  Out               = 1,
  In                = 2,
  QuadIn            = 3,
  QuadOut           = 4,
  QuadInOut         = 5,
  CubicIn           = 6,
  CubicOut          = 7,
  CubicInOut        = 8,
  QuartIn           = 9,
  QuartOut          = 10,
  QuartInOut        = 11,
  QuintIn           = 12,
  QuintOut          = 13,
  QuintInOut        = 14,
  SineIn            = 15,
  SineOut           = 16,
  SineInOut         = 17,
  ExpoIn            = 18,
  ExpoOut           = 19,
  ExpoInOut         = 20,
  CircIn            = 21,
  CircOut           = 22,
  CircInOut         = 23,
  ElasticIn         = 24,
  ElasticOut        = 25,
  ElasticHalfOut    = 26,
  ElasticQuarterOut = 27,
  ElasticInOut      = 28,
  BackIn            = 29,
  BackOut           = 30,
  BackInOut         = 31,
  BounceIn          = 32,
  BounceOut         = 33,
  BounceInOut       = 34,
}

declare enum Layer {
  Background = 'Background',
  Foreground = 'Foreground',
  Overlay    = 'Overlay',
  Pass       = 'Pass',
  Fail       = 'Fail',
}

declare enum Origin {
  TopLeft      = 'TopLeft',
  TopCentre    = 'TopCentre',
  TopRight     = 'TopRight',
  CentreLeft   = 'CentreLeft',
  Centre       = 'Centre',
  CentreRight  = 'CentreRight',
  BottomLeft   = 'BottomLeft',
  BottomCentre = 'BottomCentre',
  BottomRight  = 'BottomRight',
}

interface LoopBuilder {
  /** Fade opacity */
  fade(easing: Easing, startTime: number, endTime: number, startOpacity: number, endOpacity: number): this
  /** Move on both axes */
  move(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
  /** Move X axis only */
  moveX(easing: Easing, startTime: number, endTime: number, startX: number, endX: number): this
  /** Move Y axis only */
  moveY(easing: Easing, startTime: number, endTime: number, startY: number, endY: number): this
  /** Uniform scale */
  scale(easing: Easing, startTime: number, endTime: number, startScale: number, endScale: number): this
  /** Non-uniform (vector) scale */
  scaleVec(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
  /** Rotate (radians) */
  rotate(easing: Easing, startTime: number, endTime: number, startAngle: number, endAngle: number): this
  /** Colour tint (0–255 per channel) */
  color(easing: Easing, startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this
  /** Horizontal flip for the given time range */
  flipH(startTime: number, endTime: number): this
  /** Vertical flip for the given time range */
  flipV(startTime: number, endTime: number): this
  /** Additive blend mode for the given time range */
  additive(startTime: number, endTime: number): this
}

interface SpriteBuilder {
  /** Fade opacity */
  fade(easing: Easing, startTime: number, endTime: number, startOpacity: number, endOpacity: number): this
  /** Move on both axes */
  move(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
  /** Move X axis only */
  moveX(easing: Easing, startTime: number, endTime: number, startX: number, endX: number): this
  /** Move Y axis only */
  moveY(easing: Easing, startTime: number, endTime: number, startY: number, endY: number): this
  /** Uniform scale */
  scale(easing: Easing, startTime: number, endTime: number, startScale: number, endScale: number): this
  /** Non-uniform (vector) scale */
  scaleVec(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
  /** Rotate (radians) */
  rotate(easing: Easing, startTime: number, endTime: number, startAngle: number, endAngle: number): this
  /** Colour tint (0–255 per channel) */
  color(easing: Easing, startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this
  /** Horizontal flip for the given time range */
  flipH(startTime: number, endTime: number): this
  /** Vertical flip for the given time range */
  flipV(startTime: number, endTime: number): this
  /** Additive blend mode for the given time range */
  additive(startTime: number, endTime: number): this
  /**
   * Loop group — commands inside repeat \`loopCount\` times starting at \`startTime\`.
   * Times inside the callback are relative to the loop start.
   * @example
   * sprite('logo.png').loop(0, 4, l => {
   *   l.fade(Easing.Linear, 0, 500, 0, 1)
   *   l.fade(Easing.Linear, 500, 1000, 1, 0)
   * })
   */
  loop(startTime: number, loopCount: number, build: (l: LoopBuilder) => void): this
}

/**
 * Create a new storyboard sprite.
 * @param filePath - Image path relative to the project root
 * @param layer    - Render layer (default: Layer.Foreground)
 * @param origin   - Anchor point (default: Origin.Centre)
 * @param x        - Default X position in osu! coordinates (default: 320)
 * @param y        - Default Y position in osu! coordinates (default: 240)
 */
declare function sprite(
  filePath: string,
  layer?: Layer,
  origin?: Origin,
  x?: number,
  y?: number,
): SpriteBuilder

/**
 * Convert beats to milliseconds using the project BPM and offset.
 * @example beat(4) // ms at the 4th beat
 */
declare function beat(beats: number): number

/** Project BPM (beats per minute) */
declare const bpm: number

/** Audio offset in milliseconds */
declare const offset: number
`

// ─── Init ─────────────────────────────────────────────────────────────────────

async function initEditor() {
    if (!containerRef.value) return

    // Configure Monaco workers before importing the editor.
    // Vite exposes ?worker imports as constructors.
    const [{ default: editorWorker }, { default: tsWorker }] = await Promise.all([
        import('monaco-editor/esm/vs/editor/editor.worker?worker'),
        import('monaco-editor/esm/vs/language/typescript/ts.worker?worker'),
    ])

        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ; (self as any).MonacoEnvironment = {
            getWorker(_: unknown, label: string) {
                if (label === 'typescript' || label === 'javascript') return new tsWorker()
                return new editorWorker()
            },
        }

    const monaco = await import('monaco-editor')

    // ── TypeScript config ──────────────────────────────────────────────────────
    // monaco.languages.typescript is deprecated in types since 0.52 but still
    // functional at runtime — cast to access typescriptDefaults.
    // ScriptTarget.ES2020 = 7 (TypeScript enum value)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const tsDefaults = (monaco.languages as any).typescript?.typescriptDefaults
    if (tsDefaults) {
        tsDefaults.setCompilerOptions({
            target: 7, // ScriptTarget.ES2020
            strict: true,
            noEmit: true,
            allowNonTsExtensions: true,
        })
        tsDefaults.addExtraLib(SCRIPTING_TYPES, 'ts:storyboard-api.d.ts')
    }

    // ── Create editor ──────────────────────────────────────────────────────────
    editor = monaco.editor.create(containerRef.value, {
        value: props.modelValue,
        language: 'typescript',
        theme: 'vs-dark',
        minimap: { enabled: false },
        fontSize: 13,
        lineHeight: 20,
        fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", Consolas, monospace',
        fontLigatures: true,
        scrollBeyondLastLine: false,
        padding: { top: 12, bottom: 12 },
        readOnly: props.readonly,
        automaticLayout: true,
        tabSize: 2,
        renderLineHighlight: 'gutter',
        smoothScrolling: true,
        cursorSmoothCaretAnimation: 'on',
        suggest: {
            showEnumMembers: true,
            showFunctions: true,
            showVariables: true,
        },
    })

    editor.onDidChangeModelContent(() => {
        if (suppressNextChange) { suppressNextChange = false; return }
        const value = editor!.getValue()
        if (debounceTimer) clearTimeout(debounceTimer)
        debounceTimer = setTimeout(() => emit('update:modelValue', value), 300)
    })
}

// ─── Lifecycle ────────────────────────────────────────────────────────────────

onMounted(initEditor)

onUnmounted(() => {
    if (debounceTimer) clearTimeout(debounceTimer)
    editor?.dispose()
})

// ─── Sync modelValue from parent ──────────────────────────────────────────────

watch(() => props.modelValue, (newVal) => {
    if (!editor) return
    if (editor.getValue() !== newVal) {
        suppressNextChange = true
        editor.setValue(newVal)
    }
})
</script>

<template>
    <div ref="containerRef" class="w-full h-full" />
</template>
