/**
 * Web Worker — executes compiled storyboard scripts in an isolated context.
 *
 * Message flow:
 *   Main → Worker:  { type: 'run', code: string, bpm: number, offset: number }
 *   Worker → Main:  { type: 'result', sprites: StoryboardSprite[] }
 *                   { type: 'error',  message: string }
 */

import { createScriptContext } from '~/lib/scripting/api'
import type { StoryboardSprite } from '~/types'

// ─── Message types ────────────────────────────────────────────────────────────

interface RunMessage {
    type: 'run'
    scriptId: string
    code: string
    bpm: number
    offset: number
}

interface ResultMessage {
    type: 'result'
    sprites: StoryboardSprite[]
}

interface ErrorMessage {
    type: 'error'
    message: string
}

type WorkerInMessage = RunMessage
type WorkerOutMessage = ResultMessage | ErrorMessage

// ─── Worker handler ───────────────────────────────────────────────────────────

self.onmessage = async (event: MessageEvent<WorkerInMessage>) => {
    const msg = event.data

    if (msg.type !== 'run') return

    try {
        const sprites = await executeScript(msg.scriptId, msg.code, msg.bpm, msg.offset)
        const out: ResultMessage = { type: 'result', sprites }
        self.postMessage(out)
    } catch (err) {
        const out: ErrorMessage = {
            type: 'error',
            message: err instanceof Error ? err.message : String(err),
        }
        self.postMessage(out)
    }
}

// ─── Execution ────────────────────────────────────────────────────────────────

async function executeScript(
    scriptId: string,
    code: string,
    bpm: number,
    offset: number,
): Promise<StoryboardSprite[]> {
    const { context, getSprites } = createScriptContext(scriptId, bpm, offset)

    // Build the function that wraps user code.
    // We inject context bindings as named parameters so the user can write:
    //   sprite('logo.png').fade(Easing.SineOut, 0, 500, 0, 1)
    // without any import statements.
    const fn = new Function(
        'sprite', 'beat', 'bpm', 'offset', 'Layer', 'Origin', 'Easing', 'random', 'randomInt',
        `"use strict";\n${code}`,
    )

    await fn(
        context.sprite,
        context.beat,
        context.bpm,
        context.offset,
        context.Layer,
        context.Origin,
        context.Easing,
        context.random,
        context.randomInt,
    )

    return getSprites()
}

export type { WorkerInMessage, WorkerOutMessage }
