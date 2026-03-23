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
    // defaultX/Y used only when there are no M commands at all.
    let x = p.defaultX
    let y = p.defaultY

    if (p.M.length > 0) {
        const m = resolveCommand(p.M, timeMs)
        x = easedValue(m, timeMs, c => c.startX, c => c.endX)
        y = easedValue(m, timeMs, c => c.startY, c => c.endY)
    }
    if (p.MX.length > 0)
        x = easedValue(resolveCommand(p.MX, timeMs), timeMs, c => c.startX, c => c.endX)
    if (p.MY.length > 0)
        y = easedValue(resolveCommand(p.MY, timeMs), timeMs, c => c.startY, c => c.endY)

    // ── Scale ──
    let scaleX = 1
    let scaleY = 1

    if (p.S.length > 0) {
        const s = resolveCommand(p.S, timeMs)
        scaleX = scaleY = easedValue(s, timeMs, c => c.startScale, c => c.endScale)
    }
    if (p.V.length > 0) {
        const v = resolveCommand(p.V, timeMs)
        scaleX = easedValue(v, timeMs, c => c.startX, c => c.endX)
        scaleY = easedValue(v, timeMs, c => c.startY, c => c.endY)
    }

    // ── Rotation ──
    const rotation = p.R.length > 0
        ? easedValue(resolveCommand(p.R, timeMs), timeMs, c => c.startAngle, c => c.endAngle)
        : 0

    // ── Opacity ──
    // No F commands → always visible. Otherwise use startOpacity of first command
    const opacity = p.F.length > 0
        ? easedValue(resolveCommand(p.F, timeMs), timeMs, c => c.startOpacity, c => c.endOpacity)
        : 1

    // ── Color ──
    let r = 255
    let g = 255
    let b = 255

    if (p.C.length > 0) {
        const col = resolveCommand(p.C, timeMs)
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
        // blank endTime in .osb → parsed as endTime = startTime → hold until sprite dies
        const effectiveEnd = param.startTime === param.endTime ? p.activeEnd : param.endTime
        if (effectiveEnd < timeMs) continue
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
 * Resolves the active command at timeMs, handling overlapping commands correctly.
 * Commands must be sorted by startTime. Assumes timeMs >= commands[0].startTime.
 *
 * Priority rules:
 * - Among commands active at timeMs (startTime <= t <= endTime), pick the one
 *   with the highest startTime (most recently started = highest priority).
 * - If no command is active, hold the value of the command with the latest endTime.
 */
function resolveCommand<T extends Command>(commands: T[], timeMs: number): T {
    let bestActive: T | undefined
    let bestEnded: T | undefined

    for (const cmd of commands) {
        if (cmd.startTime > timeMs) break // sorted by startTime → can early-exit
        if (timeMs <= cmd.endTime) {
            bestActive = cmd // last assigned = highest startTime among active
        } else if (bestEnded === undefined || cmd.endTime > bestEnded.endTime) {
            bestEnded = cmd // track the most recently ended command
        }
    }

    return (bestActive ?? bestEnded ?? commands[0])!
}

function easedValue<T extends Command>(
    command: T,
    timeMs: number,
    getStart: (c: T) => number,
    getEnd: (c: T) => number,
): number {
    const { startTime, endTime, easing } = command
    if (timeMs < startTime) return getStart(command) // before command → hold start value
    if (startTime === endTime) return getEnd(command)  // instant command → end value
    const t = Math.min(1, (timeMs - startTime) / (endTime - startTime))
    return easedLerp(getStart(command), getEnd(command), t, easing)
}
