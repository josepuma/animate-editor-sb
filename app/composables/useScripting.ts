import { ref, readonly } from 'vue'
import type { StoryboardSprite } from '~/types'
import { compileScript } from '~/lib/scripting/compiler'
import type { WorkerInMessage, WorkerOutMessage } from '~/workers/script-runner'

// ─── Composable ──────────────────────────────────────────────────────────────

export type ScriptError = { message: string; phase: 'compile' | 'runtime' }

export function useScripting() {
    const sprites = ref<StoryboardSprite[]>([])
    const isRunning = ref(false)
    const errors = ref<ScriptError[]>([])

    let worker: Worker | null = null

    // ── Run ───────────────────────────────────────────────────────────────────

    /**
     * Compiles and runs a TypeScript storyboard script.
     * On success, updates `sprites`. On failure, populates `errors`.
     */
    async function run(tsSource: string, bpm: number, offset: number): Promise<void> {
        if (isRunning.value) return

        isRunning.value = true
        errors.value = []

        // 1. Compile TypeScript → JS
        const { code, errors: compileErrors } = await compileScript(tsSource)

        if (compileErrors.length) {
            errors.value = compileErrors.map(m => ({ message: m, phase: 'compile' }))
            isRunning.value = false
            return
        }

        // 2. Execute in a Web Worker
        try {
            const result = await runInWorker(code, bpm, offset)
            sprites.value = result
        } catch (err) {
            errors.value = [{
                message: err instanceof Error ? err.message : String(err),
                phase: 'runtime',
            }]
        } finally {
            isRunning.value = false
        }
    }

    function clear(): void {
        sprites.value = []
        errors.value = []
    }

    function destroy(): void {
        worker?.terminate()
        worker = null
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    function runInWorker(
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

            const msg: WorkerInMessage = { type: 'run', code, bpm, offset }
            worker.postMessage(msg)
        })
    }

    return {
        sprites: readonly(sprites),
        isRunning: readonly(isRunning),
        errors: readonly(errors),
        run,
        clear,
        destroy,
    }
}
