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

        // Active window from direct commands.
        // P (parameter) commands are modifiers that apply within the sprite's lifetime
        // but must not define the lifetime themselves — e.g. additive(0,0) is a
        // zero-duration shorthand meaning "always additive", not "alive since t=0".
        for (const c of sprite.commands) {
            if (c.type === 'P') continue
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

// Reusable state pool — avoids allocating new objects every frame.
// The pool grows lazily; objects are recycled across frames.
let statePool: SpriteRenderState[] = []
let statePoolIndex = 0

/**
 * Returns a SpriteRenderState from the pool, growing the pool if needed.
 * Call resetStatePool() at the start of each frame.
 */
function acquireState(): SpriteRenderState {
    if (statePoolIndex < statePool.length) {
        return statePool[statePoolIndex++]!
    }
    const s: SpriteRenderState = {
        spriteId: '', x: 0, y: 0, scaleX: 1, scaleY: 1,
        rotation: 0, opacity: 1, r: 255, g: 255, b: 255,
        visible: true, additive: false, flipH: false, flipV: false,
    }
    statePool.push(s)
    statePoolIndex++
    return s
}

/**
 * Resolves all active sprites at the given timestamp.
 * Returns a slice of the internal pool — valid until the next call.
 */
export function resolveStoryboard(prepared: PreparedSprite[], timeMs: number): SpriteRenderState[] {
    // Reset pool index for this frame
    statePoolIndex = 0

    let count = 0
    for (let i = 0; i < prepared.length; i++) {
        const p = prepared[i]!
        if (timeMs < p.activeStart || timeMs > p.activeEnd) continue
        const state = acquireState()
        if (resolveSprite(p, timeMs, state)) {
            count++
        } else {
            // Didn't produce a valid state — rewind pool index
            statePoolIndex--
        }
    }

    // Return a view of the pool (no allocation if count is stable across frames)
    return statePool.slice(0, count)
}

function resolveSprite(p: PreparedSprite, timeMs: number, out: SpriteRenderState): boolean {
    // ── Position ──
    let x = p.defaultX
    let y = p.defaultY

    if (p.M.length > 0) {
        const m = resolveCommand(p.M, timeMs)
        x = easedValue(m, timeMs, m.startX, m.endX)
        y = easedValue(m, timeMs, m.startY, m.endY)
    }
    if (p.MX.length > 0) {
        const mx = resolveCommand(p.MX, timeMs)
        x = easedValue(mx, timeMs, mx.startX, mx.endX)
    }
    if (p.MY.length > 0) {
        const my = resolveCommand(p.MY, timeMs)
        y = easedValue(my, timeMs, my.startY, my.endY)
    }

    // ── Scale ──
    let scaleX = 1
    let scaleY = 1

    if (p.S.length > 0) {
        const s = resolveCommand(p.S, timeMs)
        scaleX = scaleY = easedValue(s, timeMs, s.startScale, s.endScale)
    }
    if (p.V.length > 0) {
        const v = resolveCommand(p.V, timeMs)
        scaleX = easedValue(v, timeMs, v.startX, v.endX)
        scaleY = easedValue(v, timeMs, v.startY, v.endY)
    }

    // ── Rotation ──
    let rotation = 0
    if (p.R.length > 0) {
        const r = resolveCommand(p.R, timeMs)
        rotation = easedValue(r, timeMs, r.startAngle, r.endAngle)
    }

    // ── Opacity ──
    let opacity = 1
    if (p.F.length > 0) {
        const f = resolveCommand(p.F, timeMs)
        opacity = easedValue(f, timeMs, f.startOpacity, f.endOpacity)
    }

    // ── Color ──
    let r = 255, g = 255, b = 255

    if (p.C.length > 0) {
        const col = resolveCommand(p.C, timeMs)
        r = easedValue(col, timeMs, col.startR, col.endR)
        g = easedValue(col, timeMs, col.startG, col.endG)
        b = easedValue(col, timeMs, col.startB, col.endB)
    }

    // ── Parameters (direct) ──
    let additive = false, flipH = false, flipV = false

    for (let i = 0; i < p.P.length; i++) {
        const param = p.P[i]!
        if (param.startTime > timeMs) break
        const effectiveEnd = param.startTime === param.endTime ? p.activeEnd : param.endTime
        if (effectiveEnd < timeMs) continue
        if (param.parameter === 'A') additive = true
        else if (param.parameter === 'H') flipH = true
        else if (param.parameter === 'V') flipV = true
    }

    // ── Loop overrides ────────────────────────────────────────────────────────
    let hasActiveLoop = false
    let lastEndedLoop: PreparedLoop | null = null
    let lastEndedLoopEnd = -Infinity

    for (let li = 0; li < p.loops.length; li++) {
        const loop = p.loops[li]!
        const loopEnd = loop.startTime + loop.loopCount * loop.loopDuration
        if (timeMs < loop.startTime) continue

        if (timeMs >= loopEnd) {
            if (loopEnd > lastEndedLoopEnd) {
                lastEndedLoop = loop
                lastEndedLoopEnd = loopEnd
            }
            continue
        }

        hasActiveLoop = true
        const relT = (timeMs - loop.startTime) % loop.loopDuration

        if (loop.M.length > 0) {
            const m = resolveCommand(loop.M, relT)
            x = easedValue(m, relT, m.startX, m.endX)
            y = easedValue(m, relT, m.startY, m.endY)
        }
        if (loop.MX.length > 0) {
            const mx = resolveCommand(loop.MX, relT)
            x = easedValue(mx, relT, mx.startX, mx.endX)
        }
        if (loop.MY.length > 0) {
            const my = resolveCommand(loop.MY, relT)
            y = easedValue(my, relT, my.startY, my.endY)
        }

        if (loop.S.length > 0) {
            const s = resolveCommand(loop.S, relT)
            scaleX = scaleY = easedValue(s, relT, s.startScale, s.endScale)
        }
        if (loop.V.length > 0) {
            const v = resolveCommand(loop.V, relT)
            scaleX = easedValue(v, relT, v.startX, v.endX)
            scaleY = easedValue(v, relT, v.startY, v.endY)
        }

        if (loop.R.length > 0) {
            const rc = resolveCommand(loop.R, relT)
            rotation = easedValue(rc, relT, rc.startAngle, rc.endAngle)
        }

        if (loop.F.length > 0) {
            const fc = resolveCommand(loop.F, relT)
            opacity = easedValue(fc, relT, fc.startOpacity, fc.endOpacity)
        }

        if (loop.C.length > 0) {
            const col = resolveCommand(loop.C, relT)
            r = easedValue(col, relT, col.startR, col.endR)
            g = easedValue(col, relT, col.startG, col.endG)
            b = easedValue(col, relT, col.startB, col.endB)
        }

        for (let i = 0; i < loop.P.length; i++) {
            const param = loop.P[i]!
            if (param.startTime > relT) break
            const effectiveEnd = param.startTime === param.endTime ? loop.loopDuration : param.endTime
            if (effectiveEnd < relT) continue
            if (param.parameter === 'A') additive = true
            else if (param.parameter === 'H') flipH = true
            else if (param.parameter === 'V') flipV = true
        }
    }

    // If no loop is active but one has ended, hold its terminal state for loop-only properties.
    if (!hasActiveLoop && lastEndedLoop !== null) {
        const tl = lastEndedLoop
        const termT = tl.loopDuration

        if (p.M.length === 0 && tl.M.length > 0) {
            const m = resolveCommand(tl.M, termT)
            x = easedValue(m, termT, m.startX, m.endX)
            y = easedValue(m, termT, m.startY, m.endY)
        }
        if (p.MX.length === 0 && tl.MX.length > 0) {
            const mx = resolveCommand(tl.MX, termT)
            x = easedValue(mx, termT, mx.startX, mx.endX)
        }
        if (p.MY.length === 0 && tl.MY.length > 0) {
            const my = resolveCommand(tl.MY, termT)
            y = easedValue(my, termT, my.startY, my.endY)
        }

        if (p.S.length === 0 && tl.S.length > 0) {
            const s = resolveCommand(tl.S, termT)
            scaleX = scaleY = easedValue(s, termT, s.startScale, s.endScale)
        }
        if (p.V.length === 0 && tl.V.length > 0) {
            const v = resolveCommand(tl.V, termT)
            scaleX = easedValue(v, termT, v.startX, v.endX)
            scaleY = easedValue(v, termT, v.startY, v.endY)
        }

        if (p.R.length === 0 && tl.R.length > 0) {
            const rc = resolveCommand(tl.R, termT)
            rotation = easedValue(rc, termT, rc.startAngle, rc.endAngle)
        }

        if (p.F.length === 0 && tl.F.length > 0) {
            const fc = resolveCommand(tl.F, termT)
            opacity = easedValue(fc, termT, fc.startOpacity, fc.endOpacity)
        }

        if (p.C.length === 0 && tl.C.length > 0) {
            const col = resolveCommand(tl.C, termT)
            r = easedValue(col, termT, col.startR, col.endR)
            g = easedValue(col, termT, col.startG, col.endG)
            b = easedValue(col, termT, col.startB, col.endB)
        }
    }

    out.spriteId = p.id
    out.x = x
    out.y = y
    out.scaleX = scaleX
    out.scaleY = scaleY
    out.rotation = rotation
    out.opacity = opacity
    out.r = r
    out.g = g
    out.b = b
    out.visible = opacity > 0
    out.additive = additive
    out.flipH = flipH
    out.flipV = flipV

    return true
}

// ─── Internals ────────────────────────────────────────────────────────────────

function sortedGroup<T extends Command>(commands: Command[], type: T['type']): T[] {
    return (commands.filter(c => c.type === type) as T[])
        .sort((a, b) => a.startTime - b.startTime)
}

/**
 * Binary search to find the rightmost command whose startTime <= timeMs.
 * Returns the index, or -1 if all commands start after timeMs.
 */
function upperBound(commands: Command[], timeMs: number): number {
    let lo = 0
    let hi = commands.length - 1
    let result = -1
    while (lo <= hi) {
        const mid = (lo + hi) >>> 1
        if (commands[mid]!.startTime <= timeMs) {
            result = mid
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return result
}

/**
 * Resolves the active command at timeMs using binary search.
 * Commands must be sorted by startTime.
 *
 * Priority rules:
 * - Among commands active at timeMs (startTime <= t <= endTime), pick the one
 *   with the highest startTime (most recently started = highest priority).
 * - If no command is active, hold the value of the command with the latest endTime.
 */
function resolveCommand<T extends Command>(commands: T[], timeMs: number): T {
    // Binary search: find rightmost command with startTime <= timeMs
    const ub = upperBound(commands as Command[], timeMs)

    if (ub === -1) {
        // All commands start after timeMs → use first command (hold its start value)
        return commands[0]!
    }

    // Scan backwards from ub to find the best active or ended command.
    // Because commands are sorted by startTime, the highest-priority active command
    // is the one nearest ub that is still active (endTime >= timeMs).
    let bestActive: T | undefined
    let bestEnded: T | undefined

    for (let i = ub; i >= 0; i--) {
        const cmd = commands[i]!
        if (timeMs <= cmd.endTime) {
            // Active — this has the highest startTime among active (first found scanning back)
            bestActive = cmd
            break
        }
        // Ended — track the one with the highest endTime
        if (bestEnded === undefined || cmd.endTime > bestEnded.endTime ||
            (cmd.endTime === bestEnded.endTime && cmd.startTime > bestEnded.startTime)) {
            bestEnded = cmd
        }
    }

    // If we didn't find bestEnded yet and there are commands after ub that ended,
    // they can't exist (startTime > timeMs means they haven't started).
    // But we may have missed ended commands before the scan range if we broke early.
    // Since we scan all the way to 0 unless we find an active command, this is correct.

    return (bestActive ?? bestEnded ?? commands[0])!
}

/**
 * Inlined eased interpolation — avoids function-call overhead for hot path.
 * Accepts pre-extracted start/end values instead of accessor functions.
 */
function easedValue<T extends Command>(
    command: T,
    timeMs: number,
    startVal: number,
    endVal: number,
): number {
    const { startTime, endTime, easing } = command
    if (timeMs < startTime) return startVal
    if (startTime === endTime) return endVal
    const t = Math.min(1, (timeMs - startTime) / (endTime - startTime))
    return easedLerp(startVal, endVal, t, easing)
}
