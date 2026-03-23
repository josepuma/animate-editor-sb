import type { BuildResult } from 'esbuild-wasm'

let initialized = false
let initPromise: Promise<void> | null = null

// ─── Init ─────────────────────────────────────────────────────────────────────

/**
 * Initializes esbuild-wasm. Call once before the first compilation.
 * Safe to call multiple times — subsequent calls are no-ops.
 */
export async function initCompiler(): Promise<void> {
    if (initialized) return
    if (initPromise) return initPromise

    initPromise = (async () => {
        const esbuild = await import('esbuild-wasm')
        await esbuild.initialize({
            wasmURL: new URL('esbuild-wasm/esbuild.wasm', import.meta.url).href,
            worker: false, // we're already inside a Web Worker
        })
        initialized = true
    })()

    return initPromise
}

// ─── Compile ──────────────────────────────────────────────────────────────────

export interface CompileResult {
    code: string
    errors: string[]
}

/**
 * Compiles a TypeScript storyboard script to plain JS.
 * Returns the JS code on success, or a list of error messages on failure.
 */
export async function compileScript(tsSource: string): Promise<CompileResult> {
    await initCompiler()

    const esbuild = await import('esbuild-wasm')

    let result: BuildResult

    try {
        result = await esbuild.build({
            stdin: {
                contents: tsSource,
                loader: 'ts',
                sourcefile: 'script.ts',
            },
            bundle: false,
            write: false,
            format: 'cjs',
            target: 'es2020',
            // Strip type annotations only — no tree-shaking, no bundling
            tsconfigRaw: {
                compilerOptions: {
                    strict: true,
                    target: 'ES2020',
                    module: 'CommonJS',
                },
            },
        })
    } catch (err) {
        return {
            code: '',
            errors: [err instanceof Error ? err.message : String(err)],
        }
    }

    const errors = result.errors.map(e =>
        `${e.location ? `${e.location.file}:${e.location.line}:${e.location.column} ` : ''}${e.text}`,
    )

    if (errors.length) return { code: '', errors }

    const outputFile = result.outputFiles?.[0]
    const code = outputFile?.text ?? ''

    return { code, errors: [] }
}
