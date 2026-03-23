import type {
    StoryboardSprite,
    LoopGroup,
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

// ─── Pre-processed types ──────────────────────────────────────────────────────

/**
 * A loop group with commands pre-sorted by type+startTime and its iteration
 * duration pre-computed. Resolved lazily per frame via modulo arithmetic.
 */
export interface PreparedLoop {
    startTime: number
    /** Duration of one iteration = max(relative endTime) across all body commands. */
    loopDuration: number
    loopCount: number
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
    // Direct (non-loop) commands
    F: FadeCommand[]
    M: MoveCommand[]
    MX: MoveXCommand[]
    MY: MoveYCommand[]
    S: ScaleCommand[]
    V: VectorScaleCommand[]
    R: RotateCommand[]
    C: ColorCommand[]
    P: ParameterCommand[]
    // Loop groups — resolved lazily per frame
    loops: PreparedLoop[]
}

// ─── One-time preprocessing ───────────────────────────────────────────────────

export function prepareStoryboard(sprites: StoryboardSprite[]): PreparedSprite[] {
    const result: PreparedSprite[] = []

    for (const sprite of sprites) {
        const hasCommands = sprite.commands.length > 0
        const hasLoops = sprite.loops.length > 0
        if (!hasCommands && !hasLoops) continue

        let activeStart = Infinity
        let activeEnd = -Infinity

        // Active window from direct commands
        for (const c of sprite.commands) {
            if (c.startTime < activeStart) activeStart = c.startTime
            if (c.endTime > activeEnd) activeEnd = c.endTime
        }

        // Prepare loops and extend active window to cover them
        const preparedLoops: PreparedLoop[] = []
        for (const loop of sprite.loops) {
            const pl = prepareLoop(loop)
            if (!pl) continue
            preparedLoops.push(pl)
            const loopEnd = loop.startTime + loop.loopCount * pl.loopDuration
            if (loop.startTime < activeStart) activeStart = loop.startTime
            if (loopEnd > activeEnd) activeEnd = loopEnd
        }

        if (!isFinite(activeStart)) continue

        result.push({
            id: sprite.id,
            defaultX: sprite.defaultX,
            defaultY: sprite.defaultY,
            activeStart,
            activeEnd,
            F:  sortedGroup<FadeCommand>(sprite.commands, 'F'),
            M:  sortedGroup<MoveCommand>(sprite.commands, 'M'),
            MX: sortedGroup<MoveXCommand>(sprite.commands, 'MX'),
            MY: sortedGroup<MoveYCommand>(sprite.commands, 'MY'),
            S:  sortedGroup<ScaleCommand>(sprite.commands, 'S'),
            V:  sortedGroup<VectorScaleCommand>(sprite.commands, 'V'),
            R:  sortedGroup<RotateCommand>(sprite.commands, 'R'),
            C:  sortedGroup<ColorCommand>(sprite.commands, 'C'),
            P:  sortedGroup<ParameterCommand>(sprite.commands, 'P'),
            loops: preparedLoops,
        })
    }

    return result
}

function prepareLoop(loop: LoopGroup): PreparedLoop | null {
    if (loop.commands.length === 0) return null
    // loopDuration = max relative endTime across all body commands
    const loopDuration = loop.commands.reduce((max, c) => Math.max(max, c.endTime), 0)
    if (loopDuration <= 0) return null

    return {
        startTime:    loop.startTime,
        loopDuration,
        loopCount:    loop.loopCount,
        F:  sortedGroup<FadeCommand>(loop.commands, 'F'),
        M:  sortedGroup<MoveCommand>(loop.commands, 'M'),
        MX: sortedGroup<MoveXCommand>(loop.commands, 'MX'),
        MY: sortedGroup<MoveYCommand>(loop.commands, 'MY'),
        S:  sortedGroup<ScaleCommand>(loop.commands, 'S'),
        V:  sortedGroup<VectorScaleCommand>(loop.commands, 'V'),
        R:  sortedGroup<RotateCommand>(loop.commands, 'R'),
        C:  sortedGroup<ColorCommand>(loop.commands, 'C'),
        P:  sortedGroup<ParameterCommand>(loop.commands, 'P'),
    }
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
    let rotation = p.R.length > 0
        ? easedValue(resolveCommand(p.R, timeMs), timeMs, c => c.startAngle, c => c.endAngle)
        : 0

    // ── Opacity ──
    // No F commands → always visible. Otherwise use startOpacity of first command
    let opacity = p.F.length > 0
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

    // ── Parameters (direct) ──
    let additive = false, flipH = false, flipV = false

    for (const param of p.P) {
        if (param.startTime > timeMs) break
        // blank endTime → hold until sprite dies
        const effectiveEnd = param.startTime === param.endTime ? p.activeEnd : param.endTime
        if (effectiveEnd < timeMs) continue
        if (param.parameter === 'A') additive = true
        else if (param.parameter === 'H') flipH = true
        else if (param.parameter === 'V') flipV = true
    }

    // ── Loop overrides ────────────────────────────────────────────────────────
    // For each active loop: relT = position within the current iteration (relative times).
    // Loop commands override direct commands for any property they define.
    // We also track the most recently ended loop so we can hold its terminal state
    // for loop-only properties between loops (preventing default values from bleeding through).
    let hasActiveLoop = false
    let lastEndedLoop: PreparedLoop | null = null
    let lastEndedLoopEnd = -Infinity

    for (const loop of p.loops) {
        const loopEnd = loop.startTime + loop.loopCount * loop.loopDuration
        if (timeMs < loop.startTime) continue

        if (timeMs >= loopEnd) {
            // Loop has ended — track the most recently ended one
            if (loopEnd > lastEndedLoopEnd) {
                lastEndedLoop = loop
                lastEndedLoopEnd = loopEnd
            }
            continue
        }

        // Active loop
        hasActiveLoop = true

        // relT ∈ [0, loopDuration) — position within this iteration
        const relT = (timeMs - loop.startTime) % loop.loopDuration

        if (loop.M.length > 0) {
            const m = resolveCommand(loop.M, relT)
            x = easedValue(m, relT, c => c.startX, c => c.endX)
            y = easedValue(m, relT, c => c.startY, c => c.endY)
        }
        if (loop.MX.length > 0) x = easedValue(resolveCommand(loop.MX, relT), relT, c => c.startX, c => c.endX)
        if (loop.MY.length > 0) y = easedValue(resolveCommand(loop.MY, relT), relT, c => c.startY, c => c.endY)

        if (loop.S.length > 0) {
            scaleX = scaleY = easedValue(resolveCommand(loop.S, relT), relT, c => c.startScale, c => c.endScale)
        }
        if (loop.V.length > 0) {
            const v = resolveCommand(loop.V, relT)
            scaleX = easedValue(v, relT, c => c.startX, c => c.endX)
            scaleY = easedValue(v, relT, c => c.startY, c => c.endY)
        }

        if (loop.R.length > 0)
            rotation = easedValue(resolveCommand(loop.R, relT), relT, c => c.startAngle, c => c.endAngle)

        if (loop.F.length > 0)
            opacity = easedValue(resolveCommand(loop.F, relT), relT, c => c.startOpacity, c => c.endOpacity)

        if (loop.C.length > 0) {
            const col = resolveCommand(loop.C, relT)
            r = easedValue(col, relT, c => c.startR, c => c.endR)
            g = easedValue(col, relT, c => c.startG, c => c.endG)
            b = easedValue(col, relT, c => c.startB, c => c.endB)
        }

        for (const param of loop.P) {
            if (param.startTime > relT) break
            // blank endTime inside loop → hold until end of this iteration
            const effectiveEnd = param.startTime === param.endTime ? loop.loopDuration : param.endTime
            if (effectiveEnd < relT) continue
            if (param.parameter === 'A') additive = true
            else if (param.parameter === 'H') flipH = true
            else if (param.parameter === 'V') flipV = true
        }
    }

    // If no loop is active but one has ended, hold its terminal state for loop-only properties.
    // This prevents default values (opacity=1, scale=1, etc.) from bleeding through between loops.
    if (!hasActiveLoop && lastEndedLoop !== null) {
        const tl = lastEndedLoop
        const termT = tl.loopDuration // evaluate at end-of-iteration to get terminal values

        if (p.M.length === 0 && tl.M.length > 0) {
            const m = resolveCommand(tl.M, termT)
            x = easedValue(m, termT, c => c.startX, c => c.endX)
            y = easedValue(m, termT, c => c.startY, c => c.endY)
        }
        if (p.MX.length === 0 && tl.MX.length > 0)
            x = easedValue(resolveCommand(tl.MX, termT), termT, c => c.startX, c => c.endX)
        if (p.MY.length === 0 && tl.MY.length > 0)
            y = easedValue(resolveCommand(tl.MY, termT), termT, c => c.startY, c => c.endY)

        if (p.S.length === 0 && tl.S.length > 0)
            scaleX = scaleY = easedValue(resolveCommand(tl.S, termT), termT, c => c.startScale, c => c.endScale)
        if (p.V.length === 0 && tl.V.length > 0) {
            const v = resolveCommand(tl.V, termT)
            scaleX = easedValue(v, termT, c => c.startX, c => c.endX)
            scaleY = easedValue(v, termT, c => c.startY, c => c.endY)
        }

        if (p.R.length === 0 && tl.R.length > 0)
            rotation = easedValue(resolveCommand(tl.R, termT), termT, c => c.startAngle, c => c.endAngle)

        if (p.F.length === 0 && tl.F.length > 0)
            opacity = easedValue(resolveCommand(tl.F, termT), termT, c => c.startOpacity, c => c.endOpacity)

        if (p.C.length === 0 && tl.C.length > 0) {
            const col = resolveCommand(tl.C, termT)
            r = easedValue(col, termT, c => c.startR, c => c.endR)
            g = easedValue(col, termT, c => c.startG, c => c.endG)
            b = easedValue(col, termT, c => c.startB, c => c.endB)
        }
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
