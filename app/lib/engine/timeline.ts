import type {
    StoryboardSprite,
    Command,
    FadeCommand,
    MoveCommand,
    MoveXCommand,
    MoveYCommand,
    ScaleCommand,
    VectorScaleCommand,
    RotateCommand,
    ColorCommand,
    ParameterCommand,
    SpriteRenderState,
} from '~/types'
import { easedLerp } from './easing'

// ─── Pre-processed sprite ─────────────────────────────────────────────────────

/**
 * A sprite with commands pre-grouped by type and pre-sorted by startTime.
 * Build once via prepareStoryboard(), then pass to resolveStoryboard() every frame.
 */
export interface PreparedSprite {
    id: string
    defaultX: number
    defaultY: number
    activeStart: number
    activeEnd: number
    F: FadeCommand[]
    M: MoveCommand[]
    MX: MoveXCommand[]
    MY: MoveYCommand[]
    S: ScaleCommand[]
    V: VectorScaleCommand[]
    R: RotateCommand[]
    C: ColorCommand[]
    P: ParameterCommand[]
}

// ─── One-time preprocessing ───────────────────────────────────────────────────

export function prepareStoryboard(sprites: StoryboardSprite[]): PreparedSprite[] {
    const result: PreparedSprite[] = []

    for (const sprite of sprites) {
        if (sprite.commands.length === 0) continue

        let activeStart = Infinity
        let activeEnd = -Infinity
        for (const c of sprite.commands) {
            if (c.startTime < activeStart) activeStart = c.startTime
            if (c.endTime > activeEnd) activeEnd = c.endTime
        }

        result.push({
            id: sprite.id,
            defaultX: sprite.defaultX,
            defaultY: sprite.defaultY,
            activeStart,
            activeEnd,
            F: sortedGroup<FadeCommand>(sprite.commands, 'F'),
            M: sortedGroup<MoveCommand>(sprite.commands, 'M'),
            MX: sortedGroup<MoveXCommand>(sprite.commands, 'MX'),
            MY: sortedGroup<MoveYCommand>(sprite.commands, 'MY'),
            S: sortedGroup<ScaleCommand>(sprite.commands, 'S'),
            V: sortedGroup<VectorScaleCommand>(sprite.commands, 'V'),
            R: sortedGroup<RotateCommand>(sprite.commands, 'R'),
            C: sortedGroup<ColorCommand>(sprite.commands, 'C'),
            P: sortedGroup<ParameterCommand>(sprite.commands, 'P'),
        })
    }

    return result
}

// ─── Per-frame resolution ─────────────────────────────────────────────────────

export function resolveStoryboard(prepared: PreparedSprite[], timeMs: number): SpriteRenderState[] {
    const result: SpriteRenderState[] = []
    for (const p of prepared) {
        if (timeMs < p.activeStart || timeMs > p.activeEnd) continue
        const state = resolveSprite(p, timeMs)
        if (state !== null) result.push(state)
    }
    return result
}

function resolveSprite(p: PreparedSprite, timeMs: number): SpriteRenderState | null {
    // ── Position ──
    let x = p.defaultX
    let y = p.defaultY

    if (p.M.length > 0) {
        const m = binarySearch(p.M, timeMs)
        x = easedValue(m, timeMs, c => c.startX, c => c.endX)
        y = easedValue(m, timeMs, c => c.startY, c => c.endY)
    }
    if (p.MX.length > 0) x = easedValue(binarySearch(p.MX, timeMs), timeMs, c => c.startX, c => c.endX)
    if (p.MY.length > 0) y = easedValue(binarySearch(p.MY, timeMs), timeMs, c => c.startY, c => c.endY)

    // ── Scale ──
    let scaleX = 1
    let scaleY = 1

    if (p.S.length > 0) {
        const s = binarySearch(p.S, timeMs)
        scaleX = scaleY = easedValue(s, timeMs, c => c.startScale, c => c.endScale)
    }
    if (p.V.length > 0) {
        const v = binarySearch(p.V, timeMs)
        scaleX = easedValue(v, timeMs, c => c.startX, c => c.endX)
        scaleY = easedValue(v, timeMs, c => c.startY, c => c.endY)
    }

    // ── Rotation ──
    const rotation = p.R.length > 0
        ? easedValue(binarySearch(p.R, timeMs), timeMs, c => c.startAngle, c => c.endAngle)
        : 0

    // ── Opacity ──
    const opacity = p.F.length > 0
        ? easedValue(binarySearch(p.F, timeMs), timeMs, c => c.startOpacity, c => c.endOpacity)
        : 1

    // ── Color ──
    let r = 255
    let g = 255
    let b = 255

    if (p.C.length > 0) {
        const col = binarySearch(p.C, timeMs)
        r = easedValue(col, timeMs, c => c.startR, c => c.endR)
        g = easedValue(col, timeMs, c => c.startG, c => c.endG)
        b = easedValue(col, timeMs, c => c.startB, c => c.endB)
    }

    // ── Parameter flags ──
    let additive = false
    let flipH = false
    let flipV = false

    for (const param of p.P) {
        if (param.startTime > timeMs) break // sorted, can early-exit
        if (param.endTime < timeMs) continue
        if (param.parameter === 'A') additive = true
        else if (param.parameter === 'H') flipH = true
        else if (param.parameter === 'V') flipV = true
    }

    return {
        spriteId: p.id,
        x, y,
        scaleX, scaleY,
        rotation,
        opacity,
        r, g, b,
        visible: opacity > 0,
        additive,
        flipH,
        flipV,
    }
}

// ─── Internals ────────────────────────────────────────────────────────────────

function sortedGroup<T extends Command>(commands: Command[], type: T['type']): T[] {
    return (commands.filter(c => c.type === type) as T[])
        .sort((a, b) => a.startTime - b.startTime)
}

/**
 * Binary search: finds the command active at timeMs.
 * Commands must be sorted by startTime.
 * Returns the last command whose startTime <= timeMs, clamped to array bounds.
 */
function binarySearch<T extends Command>(commands: T[], timeMs: number): T {
    const first = commands[0] as T
    const last = commands[commands.length - 1] as T

    if (timeMs <= first.startTime) return first
    if (timeMs >= last.endTime) return last

    let lo = 0
    let hi = commands.length - 1

    while (lo < hi) {
        const mid = (lo + hi + 1) >> 1
        if ((commands[mid] as T).startTime <= timeMs) {
            lo = mid
        } else {
            hi = mid - 1
        }
    }

    return commands[lo] as T
}

function easedValue<T extends Command>(
    command: T,
    timeMs: number,
    getStart: (c: T) => number,
    getEnd: (c: T) => number,
): number {
    const { startTime, endTime, easing } = command
    if (startTime === endTime) return getEnd(command)
    const t = Math.max(0, Math.min(1, (timeMs - startTime) / (endTime - startTime)))
    return easedLerp(getStart(command), getEnd(command), t, easing)
}
