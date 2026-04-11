import { ref, computed, readonly } from 'vue'
import type { StoryboardSprite, TextSpriteMap } from '~/types'
import { compileScript } from '~/lib/scripting/compiler'
import type { WorkerInMessage, WorkerOutMessage } from '~/workers/script-runner'

// ─── Composable ──────────────────────────────────────────────────────────────

export type ScriptError = { message: string; phase: 'compile' | 'runtime' }

export function useScripting() {
    // Sprites keyed by script path — each script maintains its own sprite set.
    // Running one script never touches another script's sprites.
    const spritesByScript = ref<Record<string, StoryboardSprite[]>>({})
    // Text sprite definitions keyed by script path — parallel to spritesByScript.
    const textSpritesByScript = ref<Record<string, TextSpriteMap>>({})
    const isRunning = ref(false)
    const errors = ref<ScriptError[]>([])

    // Per-script sequence counters — a newer run of script X supersedes older
    // runs of X, but NEVER cancels a concurrent run of script Y.
    const runSeqMap = new Map<string, number>()

    // Per-script workers — each script gets its own worker slot.
    const workerMap = new Map<string, Worker>()

    // Count of in-flight runs (drives isRunning).
    let runningCount = 0

    // Flat view of all sprites across all scripts, in insertion order.
    const sprites = computed(() => Object.values(spritesByScript.value).flat())
    // Merged view of all text sprite definitions across all scripts.
    const textSprites = computed<TextSpriteMap>(() => Object.assign({}, ...Object.values(textSpritesByScript.value)))

    // ── Run ───────────────────────────────────────────────────────────────────

    /**
     * Compiles and runs a TypeScript storyboard script.
     * Only the sprites for `scriptId` are replaced on success.
     * Other scripts' sprites remain untouched.
     * Rapid saves to the same script cancel the previous run of that script,
     * but concurrent runs of different scripts are fully independent.
     */
    async function run(
        scriptId: string,
        tsSource: string,
        bpm: number,
        offset: number,
        imageDimensions: Record<string, { width: number; height: number }> = {},
    ): Promise<void> {
        const seq = (runSeqMap.get(scriptId) ?? 0) + 1
        runSeqMap.set(scriptId, seq)

        runningCount++
        isRunning.value = true
        errors.value = []

        // 1. Compile TypeScript → JS
        const { code, errors: compileErrors } = await compileScript(tsSource)

        // A newer run of THIS script started while compiling — bail out
        if (runSeqMap.get(scriptId) !== seq) {
            if (--runningCount === 0) isRunning.value = false
            return
        }

        if (compileErrors.length) {
            errors.value = compileErrors.map(m => ({ message: m, phase: 'compile' as const }))
            if (--runningCount === 0) isRunning.value = false
            return
        }

        // 2. Execute in a Web Worker (per-script worker, cancels previous run of same script)
        try {
            const { sprites: result, textSprites: resultTextSprites } = await runInWorker(scriptId, code, bpm, offset, imageDimensions)
            if (runSeqMap.get(scriptId) !== seq) return
            spritesByScript.value = { ...spritesByScript.value, [scriptId]: result }
            textSpritesByScript.value = { ...textSpritesByScript.value, [scriptId]: resultTextSprites }
        } catch (err) {
            if (runSeqMap.get(scriptId) !== seq) return
            errors.value = [{
                message: err instanceof Error ? err.message : String(err),
                phase: 'runtime',
            }]
        } finally {
            if (--runningCount === 0) isRunning.value = false
        }
    }

    /**
     * Clears sprites for a specific script, or all scripts if no id is given.
     */
    function clear(scriptId?: string): void {
        if (scriptId !== undefined) {
            const next = { ...spritesByScript.value }
            delete next[scriptId]
            spritesByScript.value = next
            const nextText = { ...textSpritesByScript.value }
            delete nextText[scriptId]
            textSpritesByScript.value = nextText
        } else {
            spritesByScript.value = {}
            textSpritesByScript.value = {}
        }
        errors.value = []
    }

    function destroy(): void {
        workerMap.forEach(w => w.terminate())
        workerMap.clear()
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    function runInWorker(
        scriptId: string,
        code: string,
        bpm: number,
        offset: number,
        imageDimensions: Record<string, { width: number; height: number }>,
    ): Promise<{ sprites: StoryboardSprite[]; textSprites: TextSpriteMap }> {
        return new Promise((resolve, reject) => {
            // Terminate any previous worker for this specific script
            workerMap.get(scriptId)?.terminate()
            const w = new Worker(
                new URL('~/workers/script-runner.ts', import.meta.url),
                { type: 'module' },
            )
            workerMap.set(scriptId, w)

            const timeout = setTimeout(() => {
                w.terminate()
                workerMap.delete(scriptId)
                reject(new Error('Script timed out (5s)'))
            }, 5_000)

            w.onmessage = (event: MessageEvent<WorkerOutMessage>) => {
                clearTimeout(timeout)
                const msg = event.data

                if (msg.type === 'result') {
                    resolve({ sprites: msg.sprites, textSprites: msg.textSprites })
                } else {
                    reject(new Error(msg.message))
                }

                w.terminate()
                workerMap.delete(scriptId)
            }

            w.onerror = (err: ErrorEvent) => {
                clearTimeout(timeout)
                reject(new Error(err.message))
                w.terminate()
                workerMap.delete(scriptId)
            }

            const msg: WorkerInMessage = { type: 'run', scriptId, code, bpm, offset, imageDimensions }
            w.postMessage(msg)
        })
    }

    return {
        sprites,
        textSprites,
        spritesByScript: readonly(spritesByScript),
        isRunning: readonly(isRunning),
        errors: readonly(errors),
        run,
        clear,
        destroy,
    }
}
