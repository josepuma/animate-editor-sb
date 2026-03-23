import { Layer, Origin, Easing } from '~/types'
import type {
    Storyboard,
    StoryboardSprite,
    LoopGroup,
    Command,
} from '~/types'

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Parses the contents of a .osb (or .osu [Events] section) file
 * into a Storyboard object.
 */
export function parseOsb(source: string): Storyboard {
    const lines = source.split(/\r?\n/)
    const sprites: StoryboardSprite[] = []
    const variables: Record<string, string> = {}

    let section = ''
    let currentSprite: StoryboardSprite | null = null
    let spriteIndex = 0
    let currentLoop: LoopGroup | null = null

    for (const raw of lines) {
        const line = raw.trimEnd()

        // ── Section headers ──
        if (line.startsWith('[')) {
            commitLoop(currentLoop, currentSprite)
            currentLoop = null
            section = line
            continue
        }

        // ── Variables ──
        if (section === '[Variables]') {
            const eq = line.indexOf('=')
            if (eq !== -1) variables[line.slice(0, eq).trim()] = line.slice(eq + 1).trim()
            continue
        }

        if (section !== '[Events]') continue
        if (!line || line.startsWith('//')) continue

        const depth = indentDepth(line)

        if (depth === 0) {
            // New sprite — commit any open loop first
            commitLoop(currentLoop, currentSprite)
            currentLoop = null
            currentSprite = parseSpriteLine(line, spriteIndex++)
            if (currentSprite) sprites.push(currentSprite)
        } else if (currentSprite) {
            const trimmed = line.trim()
            const clean = trimmed.replace(/^_+/, '')
            const type = clean.split(',')[0]?.trim() ?? ''

            if (depth === 1 && type === 'L') {
                // Loop header — commit previous loop and start a new one
                commitLoop(currentLoop, currentSprite)
                const parts = clean.split(',')
                currentLoop = {
                    startTime: parseInt(parts[1] ?? '0', 10),
                    loopCount: Math.max(1, parseInt(parts[2] ?? '1', 10)),
                    commands: [],
                }
            } else if (depth >= 2 && currentLoop !== null) {
                // Command inside loop body — times are relative to the loop iteration
                const cmd = parseCommandLine(trimmed)
                if (cmd) currentLoop.commands.push(cmd)
            } else {
                // Direct command (depth 1, not L) — commit any open loop first
                commitLoop(currentLoop, currentSprite)
                currentLoop = null
                const cmd = parseCommandLine(trimmed)
                if (cmd) currentSprite.commands.push(cmd)
            }
        }
    }

    // Commit any loop still open at EOF
    commitLoop(currentLoop, currentSprite)

    return {
        sprites,
        variables: Object.keys(variables).length ? variables : undefined,
    }
}

// ─── Loop helpers ─────────────────────────────────────────────────────────────

/** Pushes a completed loop into the sprite's loops array. */
function commitLoop(loop: LoopGroup | null, sprite: StoryboardSprite | null): void {
    if (loop && sprite && loop.commands.length > 0) sprite.loops.push(loop)
}

/** Counts leading underscore/space characters to determine nesting depth. */
function indentDepth(line: string): number {
    let d = 0
    for (const ch of line) {
        if (ch === '_' || ch === ' ') d++
        else break
    }
    return d
}

// ─── Sprite parser ────────────────────────────────────────────────────────────

function parseSpriteLine(line: string, index: number): StoryboardSprite | null {
    // Sprite,Layer,Origin,"filepath",x,y
    // Animation,Layer,Origin,"filepath",x,y,frameCount,frameDelay,loopType
    const parts = splitCsv(line)
    const type = parts[0]?.trim()

    if (type !== 'Sprite' && type !== 'Animation') return null

    const layer = parseLayer(parts[1]?.trim() ?? '')
    const origin = parseOrigin(parts[2]?.trim() ?? '')
    const filePath = (parts[3] ?? '').trim().replace(/^"|"$/g, '')
    const x = parseFloat(parts[4] ?? '320') || 320
    const y = parseFloat(parts[5] ?? '240') || 240

    return {
        id: `sprite_${index}`,
        layer,
        origin,
        filePath,
        defaultX: x,
        defaultY: y,
        commands: [],
        loops: [],
    }
}

// ─── Command parser ───────────────────────────────────────────────────────────

function parseCommandLine(line: string): Command | null {
    // Strip leading underscores (loop/trigger nesting — treat as top-level for now)
    const clean = line.replace(/^_+/, '')
    const parts = clean.split(',')
    const type = parts[0]?.trim() ?? ''
    const e = parseInt(parts[1] ?? '0', 10) as Easing
    const t0 = parseInt(parts[2] ?? '0', 10)
    // endTime can be blank → same as startTime (instant command)
    const t1 = parts[3]?.trim() !== '' ? parseInt(parts[3] ?? '0', 10) : t0

    switch (type) {
        case 'F': {
            const s = parseFloat(parts[4] ?? '0')
            const en = parts[5]?.trim() !== '' ? parseFloat(parts[5] ?? String(s)) : s
            return { type: 'F', easing: e, startTime: t0, endTime: t1, startOpacity: s, endOpacity: en }
        }
        case 'M': {
            const sx = parseFloat(parts[4] ?? '0')
            const sy = parseFloat(parts[5] ?? '0')
            const ex = parts[6]?.trim() !== '' ? parseFloat(parts[6] ?? String(sx)) : sx
            const ey = parts[7]?.trim() !== '' ? parseFloat(parts[7] ?? String(sy)) : sy
            return { type: 'M', easing: e, startTime: t0, endTime: t1, startX: sx, startY: sy, endX: ex, endY: ey }
        }
        case 'MX': {
            const sx = parseFloat(parts[4] ?? '0')
            const ex = parts[5]?.trim() !== '' ? parseFloat(parts[5] ?? String(sx)) : sx
            return { type: 'MX', easing: e, startTime: t0, endTime: t1, startX: sx, endX: ex }
        }
        case 'MY': {
            const sy = parseFloat(parts[4] ?? '0')
            const ey = parts[5]?.trim() !== '' ? parseFloat(parts[5] ?? String(sy)) : sy
            return { type: 'MY', easing: e, startTime: t0, endTime: t1, startY: sy, endY: ey }
        }
        case 'S': {
            const ss = parseFloat(parts[4] ?? '1')
            const es = parts[5]?.trim() !== '' ? parseFloat(parts[5] ?? String(ss)) : ss
            return { type: 'S', easing: e, startTime: t0, endTime: t1, startScale: ss, endScale: es }
        }
        case 'V': {
            const sx = parseFloat(parts[4] ?? '1')
            const sy = parseFloat(parts[5] ?? '1')
            const ex = parts[6]?.trim() !== '' ? parseFloat(parts[6] ?? String(sx)) : sx
            const ey = parts[7]?.trim() !== '' ? parseFloat(parts[7] ?? String(sy)) : sy
            return { type: 'V', easing: e, startTime: t0, endTime: t1, startX: sx, startY: sy, endX: ex, endY: ey }
        }
        case 'R': {
            const sa = parseFloat(parts[4] ?? '0')
            const ea = parts[5]?.trim() !== '' ? parseFloat(parts[5] ?? String(sa)) : sa
            return { type: 'R', easing: e, startTime: t0, endTime: t1, startAngle: sa, endAngle: ea }
        }
        case 'C': {
            const sr = parseFloat(parts[4] ?? '255')
            const sg = parseFloat(parts[5] ?? '255')
            const sb = parseFloat(parts[6] ?? '255')
            const er = parts[7]?.trim() !== '' ? parseFloat(parts[7] ?? String(sr)) : sr
            const eg = parts[8]?.trim() !== '' ? parseFloat(parts[8] ?? String(sg)) : sg
            const eb = parts[9]?.trim() !== '' ? parseFloat(parts[9] ?? String(sb)) : sb
            return { type: 'C', easing: e, startTime: t0, endTime: t1, startR: sr, startG: sg, startB: sb, endR: er, endG: eg, endB: eb }
        }
        case 'P': {
            const param = (parts[4]?.trim() ?? 'H') as 'H' | 'V' | 'A'
            return { type: 'P', easing: e, startTime: t0, endTime: t1, parameter: param }
        }
        // L (loop) and T (trigger) are not supported yet
        default:
            return null
    }
}

// ─── Enum parsers ─────────────────────────────────────────────────────────────

function parseLayer(s: string): Layer {
    switch (s) {
        case 'Background': return Layer.Background
        case 'Foreground': return Layer.Foreground
        case 'Overlay': return Layer.Overlay
        case 'Pass': return Layer.Pass
        case 'Fail': return Layer.Fail
        default: return Layer.Foreground
    }
}

function parseOrigin(s: string): Origin {
    switch (s) {
        case 'TopLeft': return Origin.TopLeft
        case 'TopCentre': return Origin.TopCentre
        case 'TopRight': return Origin.TopRight
        case 'CentreLeft': return Origin.CentreLeft
        case 'Centre': return Origin.Centre
        case 'CentreRight': return Origin.CentreRight
        case 'BottomLeft': return Origin.BottomLeft
        case 'BottomCentre': return Origin.BottomCentre
        case 'BottomRight': return Origin.BottomRight
        default: return Origin.Centre
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Splits a CSV line respecting quoted strings.
 * e.g.: Sprite,Foreground,Centre,"sb/logo.png",320,240
 */
function splitCsv(line: string): string[] {
    const result: string[] = []
    let current = ''
    let inQuote = false

    for (const ch of line) {
        if (ch === '"') {
            inQuote = !inQuote
            current += ch
        } else if (ch === ',' && !inQuote) {
            result.push(current)
            current = ''
        } else {
            current += ch
        }
    }
    result.push(current)
    return result
}
