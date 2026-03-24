import { ref, computed, readonly } from 'vue'
import type { StoryboardSprite } from '~/types'
import { compileScript } from '~/lib/scripting/compiler'
import type { WorkerInMessage, WorkerOutMessage } from '~/workers/script-runner'

// ─── Composable ──────────────────────────────────────────────────────────────

export type ScriptError = { message: string; phase: 'compile' | 'runtime' }

export function useScripting() {
    // Sprites keyed by script path — each script maintains its own sprite set.
    // Running one script never touches another script's sprites.
    const spritesByScript = ref<Record<string, StoryboardSprite[]>>({})
    const isRunning = ref(false)
    const errors = ref<ScriptError[]>([])

    let worker: Worker | null = null

    // Flat view of all sprites across all scripts, in insertion order.
    const sprites = computed(() => Object.values(spritesByScript.value).flat())

    // Monotonically increasing counter — each call to run() gets a unique token.
    // If a newer run supersedes this one, we discard the result instead of applying it.
    let runSeq = 0

    // ── Run ───────────────────────────────────────────────────────────────────

    /**
     * Compiles and runs a TypeScript storyboard script.
     * Only the sprites for `scriptId` are replaced on success.
     * Other scripts' sprites remain untouched.
     * If called while a previous run is in progress the previous worker is
     * cancelled and the new run takes over — no silent drops.
     */
    async function run(scriptId: string, tsSource: string, bpm: number, offset: number): Promise<void> {
        const seq = ++runSeq

        isRunning.value = true
        errors.value = []

        // 1. Compile TypeScript → JS
        const { code, errors: compileErrors } = await compileScript(tsSource)

        // A newer run was started while we were compiling — bail out
        if (seq !== runSeq) return

        if (compileErrors.length) {
            errors.value = compileErrors.map(m => ({ message: m, phase: 'compile' as const }))
            isRunning.value = false
            return
        }

        // 2. Execute in a Web Worker (runInWorker cancels any previous worker)
        try {
            const result = await runInWorker(scriptId, code, bpm, offset)
            if (seq !== runSeq) return  // superseded while worker was running
            // Shallow-copy the map so Vue detects the change, then update only this script
            spritesByScript.value = { ...spritesByScript.value, [scriptId]: result }
        } catch (err) {
            if (seq !== runSeq) return
            errors.value = [{
                message: err instanceof Error ? err.message : String(err),
                phase: 'runtime',
            }]
        } finally {
            if (seq === runSeq) isRunning.value = false
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
        } else {
            spritesByScript.value = {}
        }
        errors.value = []
    }

    function destroy(): void {
        worker?.terminate()
        worker = null
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    function runInWorker(
        scriptId: string,
        code: string,
        bpm: number,
        offset: number,
    ): Promise<StoryboardSprite[]> {
        return new Promise((resolve, reject) => {
            // Terminate any previous worker
            worker?.terminate()
            worker = new Worker(
                new URL('~/workers/script-runner.ts', import.meta.url),
                { type: 'module' },
            )

            const timeout = setTimeout(() => {
                worker?.terminate()
                worker = null
                reject(new Error('Script timed out (5s)'))
            }, 5_000)

            worker.onmessage = (event: MessageEvent<WorkerOutMessage>) => {
                clearTimeout(timeout)
                const msg = event.data

                if (msg.type === 'result') {
                    resolve(msg.sprites)
                } else {
                    reject(new Error(msg.message))
                }

                worker?.terminate()
                worker = null
            }

            worker.onerror = (err) => {
                clearTimeout(timeout)
                reject(new Error(err.message))
                worker?.terminate()
                worker = null
            }

            const msg: WorkerInMessage = { type: 'run', scriptId, code, bpm, offset }
            worker.postMessage(msg)
        })
    }

    return {
        sprites,
        isRunning: readonly(isRunning),
        errors: readonly(errors),
        run,
        clear,
        destroy,
    }
}
