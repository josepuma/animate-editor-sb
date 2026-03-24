import { Layer, Origin, Easing } from '~/types'
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
} from '~/types'

// ─── LoopBuilder ──────────────────────────────────────────────────────────────

export class LoopBuilder {
    readonly _group: LoopGroup

    constructor(startTime: number, loopCount: number) {
        this._group = { startTime, loopCount, commands: [] }
    }

    // fade(time, value)
    fade(time: number, value: number): this
    // fade(startTime, endTime, startOpacity, endOpacity)
    fade(startTime: number, endTime: number, startOpacity: number, endOpacity: number): this
    // fade(easing, startTime, endTime, startOpacity, endOpacity)
    fade(easing: Easing, startTime: number, endTime: number, startOpacity: number, endOpacity: number): this
    fade(...args: number[]): this {
        if (args.length === 2) {
            const [time, value] = args as [number, number]
            this._push<FadeCommand>({ type: 'F', easing: Easing.Linear, startTime: time, endTime: time, startOpacity: value, endOpacity: value })
        } else if (args.length === 4) {
            const [startTime, endTime, startOpacity, endOpacity] = args as [number, number, number, number]
            this._push<FadeCommand>({ type: 'F', easing: Easing.Linear, startTime, endTime, startOpacity, endOpacity })
        } else {
            const [easing, startTime, endTime, startOpacity, endOpacity] = args as [Easing, number, number, number, number]
            this._push<FadeCommand>({ type: 'F', easing, startTime, endTime, startOpacity, endOpacity })
        }
        return this
    }

    // move(time, x, y)
    move(time: number, x: number, y: number): this
    // move(startTime, endTime, startX, startY, endX, endY)
    move(startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    // move(easing, startTime, endTime, startX, startY, endX, endY)
    move(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    move(...args: number[]): this {
        if (args.length === 3) {
            const [time, x, y] = args as [number, number, number]
            this._push<MoveCommand>({ type: 'M', easing: Easing.Linear, startTime: time, endTime: time, startX: x, startY: y, endX: x, endY: y })
        } else if (args.length === 6) {
            const [startTime, endTime, startX, startY, endX, endY] = args as [number, number, number, number, number, number]
            this._push<MoveCommand>({ type: 'M', easing: Easing.Linear, startTime, endTime, startX, startY, endX, endY })
        } else {
            const [easing, startTime, endTime, startX, startY, endX, endY] = args as [Easing, number, number, number, number, number, number]
            this._push<MoveCommand>({ type: 'M', easing, startTime, endTime, startX, startY, endX, endY })
        }
        return this
    }

    // moveX(time, x)
    moveX(time: number, x: number): this
    // moveX(startTime, endTime, startX, endX)
    moveX(startTime: number, endTime: number, startX: number, endX: number): this
    // moveX(easing, startTime, endTime, startX, endX)
    moveX(easing: Easing, startTime: number, endTime: number, startX: number, endX: number): this
    moveX(...args: number[]): this {
        if (args.length === 2) {
            const [time, x] = args as [number, number]
            this._push<MoveXCommand>({ type: 'MX', easing: Easing.Linear, startTime: time, endTime: time, startX: x, endX: x })
        } else if (args.length === 4) {
            const [startTime, endTime, startX, endX] = args as [number, number, number, number]
            this._push<MoveXCommand>({ type: 'MX', easing: Easing.Linear, startTime, endTime, startX, endX })
        } else {
            const [easing, startTime, endTime, startX, endX] = args as [Easing, number, number, number, number]
            this._push<MoveXCommand>({ type: 'MX', easing, startTime, endTime, startX, endX })
        }
        return this
    }

    // moveY(time, y)
    moveY(time: number, y: number): this
    // moveY(startTime, endTime, startY, endY)
    moveY(startTime: number, endTime: number, startY: number, endY: number): this
    // moveY(easing, startTime, endTime, startY, endY)
    moveY(easing: Easing, startTime: number, endTime: number, startY: number, endY: number): this
    moveY(...args: number[]): this {
        if (args.length === 2) {
            const [time, y] = args as [number, number]
            this._push<MoveYCommand>({ type: 'MY', easing: Easing.Linear, startTime: time, endTime: time, startY: y, endY: y })
        } else if (args.length === 4) {
            const [startTime, endTime, startY, endY] = args as [number, number, number, number]
            this._push<MoveYCommand>({ type: 'MY', easing: Easing.Linear, startTime, endTime, startY, endY })
        } else {
            const [easing, startTime, endTime, startY, endY] = args as [Easing, number, number, number, number]
            this._push<MoveYCommand>({ type: 'MY', easing, startTime, endTime, startY, endY })
        }
        return this
    }

    // scale(time, value)
    scale(time: number, value: number): this
    // scale(startTime, endTime, startScale, endScale)
    scale(startTime: number, endTime: number, startScale: number, endScale: number): this
    // scale(easing, startTime, endTime, startScale, endScale)
    scale(easing: Easing, startTime: number, endTime: number, startScale: number, endScale: number): this
    scale(...args: number[]): this {
        if (args.length === 2) {
            const [time, value] = args as [number, number]
            this._push<ScaleCommand>({ type: 'S', easing: Easing.Linear, startTime: time, endTime: time, startScale: value, endScale: value })
        } else if (args.length === 4) {
            const [startTime, endTime, startScale, endScale] = args as [number, number, number, number]
            this._push<ScaleCommand>({ type: 'S', easing: Easing.Linear, startTime, endTime, startScale, endScale })
        } else {
            const [easing, startTime, endTime, startScale, endScale] = args as [Easing, number, number, number, number]
            this._push<ScaleCommand>({ type: 'S', easing, startTime, endTime, startScale, endScale })
        }
        return this
    }

    // scaleVec(time, x, y)
    scaleVec(time: number, x: number, y: number): this
    // scaleVec(startTime, endTime, startX, startY, endX, endY)
    scaleVec(startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    // scaleVec(easing, startTime, endTime, startX, startY, endX, endY)
    scaleVec(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    scaleVec(...args: number[]): this {
        if (args.length === 3) {
            const [time, x, y] = args as [number, number, number]
            this._push<VectorScaleCommand>({ type: 'V', easing: Easing.Linear, startTime: time, endTime: time, startX: x, startY: y, endX: x, endY: y })
        } else if (args.length === 6) {
            const [startTime, endTime, startX, startY, endX, endY] = args as [number, number, number, number, number, number]
            this._push<VectorScaleCommand>({ type: 'V', easing: Easing.Linear, startTime, endTime, startX, startY, endX, endY })
        } else {
            const [easing, startTime, endTime, startX, startY, endX, endY] = args as [Easing, number, number, number, number, number, number]
            this._push<VectorScaleCommand>({ type: 'V', easing, startTime, endTime, startX, startY, endX, endY })
        }
        return this
    }

    // rotate(time, angle)
    rotate(time: number, angle: number): this
    // rotate(startTime, endTime, startAngle, endAngle)
    rotate(startTime: number, endTime: number, startAngle: number, endAngle: number): this
    // rotate(easing, startTime, endTime, startAngle, endAngle)
    rotate(easing: Easing, startTime: number, endTime: number, startAngle: number, endAngle: number): this
    rotate(...args: number[]): this {
        if (args.length === 2) {
            const [time, angle] = args as [number, number]
            this._push<RotateCommand>({ type: 'R', easing: Easing.Linear, startTime: time, endTime: time, startAngle: angle, endAngle: angle })
        } else if (args.length === 4) {
            const [startTime, endTime, startAngle, endAngle] = args as [number, number, number, number]
            this._push<RotateCommand>({ type: 'R', easing: Easing.Linear, startTime, endTime, startAngle, endAngle })
        } else {
            const [easing, startTime, endTime, startAngle, endAngle] = args as [Easing, number, number, number, number]
            this._push<RotateCommand>({ type: 'R', easing, startTime, endTime, startAngle, endAngle })
        }
        return this
    }

    // color(time, r, g, b)
    color(time: number, r: number, g: number, b: number): this
    // color(startTime, endTime, startR, startG, startB, endR, endG, endB)
    color(startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this
    // color(easing, startTime, endTime, startR, startG, startB, endR, endG, endB)
    color(easing: Easing, startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this
    color(...args: number[]): this {
        if (args.length === 4) {
            const [time, r, g, b] = args as [number, number, number, number]
            this._push<ColorCommand>({ type: 'C', easing: Easing.Linear, startTime: time, endTime: time, startR: r, startG: g, startB: b, endR: r, endG: g, endB: b })
        } else if (args.length === 8) {
            const [startTime, endTime, startR, startG, startB, endR, endG, endB] = args as [number, number, number, number, number, number, number, number]
            this._push<ColorCommand>({ type: 'C', easing: Easing.Linear, startTime, endTime, startR, startG, startB, endR, endG, endB })
        } else {
            const [easing, startTime, endTime, startR, startG, startB, endR, endG, endB] = args as [Easing, number, number, number, number, number, number, number, number]
            this._push<ColorCommand>({ type: 'C', easing, startTime, endTime, startR, startG, startB, endR, endG, endB })
        }
        return this
    }

    flipH(startTime: number, endTime: number): this {
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime, parameter: 'H' })
        return this
    }

    flipV(startTime: number, endTime: number): this {
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime, parameter: 'V' })
        return this
    }

    additive(startTime: number, endTime: number): this {
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime, parameter: 'A' })
        return this
    }

    private _push<T extends Command>(cmd: T): void {
        this._group.commands.push(cmd)
    }
}

// ─── SpriteBuilder ────────────────────────────────────────────────────────────

let _idCounter = 0

export class SpriteBuilder {
    private readonly _sprite: StoryboardSprite

    constructor(filePath: string, layer: Layer, origin: Origin, x = 320, y = 240) {
        this._sprite = {
            id: `sprite_${++_idCounter}`,
            layer,
            origin,
            filePath,
            defaultX: x,
            defaultY: y,
            commands: [],
            loops: [],
        }
    }

    // ── Commands ────────────────────────────────────────────────────────────────

    /** _F — Fade opacity */
    // fade(time, value)
    fade(time: number, value: number): this
    // fade(startTime, endTime, startOpacity, endOpacity)
    fade(startTime: number, endTime: number, startOpacity: number, endOpacity: number): this
    // fade(easing, startTime, endTime, startOpacity, endOpacity)
    fade(easing: Easing, startTime: number, endTime: number, startOpacity: number, endOpacity: number): this
    fade(...args: number[]): this {
        if (args.length === 2) {
            const [time, value] = args as [number, number]
            this._push<FadeCommand>({ type: 'F', easing: Easing.Linear, startTime: time, endTime: time, startOpacity: value, endOpacity: value })
        } else if (args.length === 4) {
            const [startTime, endTime, startOpacity, endOpacity] = args as [number, number, number, number]
            this._push<FadeCommand>({ type: 'F', easing: Easing.Linear, startTime, endTime, startOpacity, endOpacity })
        } else {
            const [easing, startTime, endTime, startOpacity, endOpacity] = args as [Easing, number, number, number, number]
            this._push<FadeCommand>({ type: 'F', easing, startTime, endTime, startOpacity, endOpacity })
        }
        return this
    }

    /** _M — Move (both axes) */
    // move(time, x, y)
    move(time: number, x: number, y: number): this
    // move(startTime, endTime, startX, startY, endX, endY)
    move(startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    // move(easing, startTime, endTime, startX, startY, endX, endY)
    move(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    move(...args: number[]): this {
        if (args.length === 3) {
            const [time, x, y] = args as [number, number, number]
            this._push<MoveCommand>({ type: 'M', easing: Easing.Linear, startTime: time, endTime: time, startX: x, startY: y, endX: x, endY: y })
        } else if (args.length === 6) {
            const [startTime, endTime, startX, startY, endX, endY] = args as [number, number, number, number, number, number]
            this._push<MoveCommand>({ type: 'M', easing: Easing.Linear, startTime, endTime, startX, startY, endX, endY })
        } else {
            const [easing, startTime, endTime, startX, startY, endX, endY] = args as [Easing, number, number, number, number, number, number]
            this._push<MoveCommand>({ type: 'M', easing, startTime, endTime, startX, startY, endX, endY })
        }
        return this
    }

    /** _MX — Move X axis only */
    // moveX(time, x)
    moveX(time: number, x: number): this
    // moveX(startTime, endTime, startX, endX)
    moveX(startTime: number, endTime: number, startX: number, endX: number): this
    // moveX(easing, startTime, endTime, startX, endX)
    moveX(easing: Easing, startTime: number, endTime: number, startX: number, endX: number): this
    moveX(...args: number[]): this {
        if (args.length === 2) {
            const [time, x] = args as [number, number]
            this._push<MoveXCommand>({ type: 'MX', easing: Easing.Linear, startTime: time, endTime: time, startX: x, endX: x })
        } else if (args.length === 4) {
            const [startTime, endTime, startX, endX] = args as [number, number, number, number]
            this._push<MoveXCommand>({ type: 'MX', easing: Easing.Linear, startTime, endTime, startX, endX })
        } else {
            const [easing, startTime, endTime, startX, endX] = args as [Easing, number, number, number, number]
            this._push<MoveXCommand>({ type: 'MX', easing, startTime, endTime, startX, endX })
        }
        return this
    }

    /** _MY — Move Y axis only */
    // moveY(time, y)
    moveY(time: number, y: number): this
    // moveY(startTime, endTime, startY, endY)
    moveY(startTime: number, endTime: number, startY: number, endY: number): this
    // moveY(easing, startTime, endTime, startY, endY)
    moveY(easing: Easing, startTime: number, endTime: number, startY: number, endY: number): this
    moveY(...args: number[]): this {
        if (args.length === 2) {
            const [time, y] = args as [number, number]
            this._push<MoveYCommand>({ type: 'MY', easing: Easing.Linear, startTime: time, endTime: time, startY: y, endY: y })
        } else if (args.length === 4) {
            const [startTime, endTime, startY, endY] = args as [number, number, number, number]
            this._push<MoveYCommand>({ type: 'MY', easing: Easing.Linear, startTime, endTime, startY, endY })
        } else {
            const [easing, startTime, endTime, startY, endY] = args as [Easing, number, number, number, number]
            this._push<MoveYCommand>({ type: 'MY', easing, startTime, endTime, startY, endY })
        }
        return this
    }

    /** _S — Uniform scale */
    // scale(time, value)
    scale(time: number, value: number): this
    // scale(startTime, endTime, startScale, endScale)
    scale(startTime: number, endTime: number, startScale: number, endScale: number): this
    // scale(easing, startTime, endTime, startScale, endScale)
    scale(easing: Easing, startTime: number, endTime: number, startScale: number, endScale: number): this
    scale(...args: number[]): this {
        if (args.length === 2) {
            const [time, value] = args as [number, number]
            this._push<ScaleCommand>({ type: 'S', easing: Easing.Linear, startTime: time, endTime: time, startScale: value, endScale: value })
        } else if (args.length === 4) {
            const [startTime, endTime, startScale, endScale] = args as [number, number, number, number]
            this._push<ScaleCommand>({ type: 'S', easing: Easing.Linear, startTime, endTime, startScale, endScale })
        } else {
            const [easing, startTime, endTime, startScale, endScale] = args as [Easing, number, number, number, number]
            this._push<ScaleCommand>({ type: 'S', easing, startTime, endTime, startScale, endScale })
        }
        return this
    }

    /** _V — Vector (non-uniform) scale */
    // scaleVec(time, x, y)
    scaleVec(time: number, x: number, y: number): this
    // scaleVec(startTime, endTime, startX, startY, endX, endY)
    scaleVec(startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    // scaleVec(easing, startTime, endTime, startX, startY, endX, endY)
    scaleVec(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this
    scaleVec(...args: number[]): this {
        if (args.length === 3) {
            const [time, x, y] = args as [number, number, number]
            this._push<VectorScaleCommand>({ type: 'V', easing: Easing.Linear, startTime: time, endTime: time, startX: x, startY: y, endX: x, endY: y })
        } else if (args.length === 6) {
            const [startTime, endTime, startX, startY, endX, endY] = args as [number, number, number, number, number, number]
            this._push<VectorScaleCommand>({ type: 'V', easing: Easing.Linear, startTime, endTime, startX, startY, endX, endY })
        } else {
            const [easing, startTime, endTime, startX, startY, endX, endY] = args as [Easing, number, number, number, number, number, number]
            this._push<VectorScaleCommand>({ type: 'V', easing, startTime, endTime, startX, startY, endX, endY })
        }
        return this
    }

    /** _R — Rotate (radians) */
    // rotate(time, angle)
    rotate(time: number, angle: number): this
    // rotate(startTime, endTime, startAngle, endAngle)
    rotate(startTime: number, endTime: number, startAngle: number, endAngle: number): this
    // rotate(easing, startTime, endTime, startAngle, endAngle)
    rotate(easing: Easing, startTime: number, endTime: number, startAngle: number, endAngle: number): this
    rotate(...args: number[]): this {
        if (args.length === 2) {
            const [time, angle] = args as [number, number]
            this._push<RotateCommand>({ type: 'R', easing: Easing.Linear, startTime: time, endTime: time, startAngle: angle, endAngle: angle })
        } else if (args.length === 4) {
            const [startTime, endTime, startAngle, endAngle] = args as [number, number, number, number]
            this._push<RotateCommand>({ type: 'R', easing: Easing.Linear, startTime, endTime, startAngle, endAngle })
        } else {
            const [easing, startTime, endTime, startAngle, endAngle] = args as [Easing, number, number, number, number]
            this._push<RotateCommand>({ type: 'R', easing, startTime, endTime, startAngle, endAngle })
        }
        return this
    }

    /** _C — Colour tint (0–255 per channel) */
    // color(time, r, g, b)
    color(time: number, r: number, g: number, b: number): this
    // color(startTime, endTime, startR, startG, startB, endR, endG, endB)
    color(startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this
    // color(easing, startTime, endTime, startR, startG, startB, endR, endG, endB)
    color(easing: Easing, startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this
    color(...args: number[]): this {
        if (args.length === 4) {
            const [time, r, g, b] = args as [number, number, number, number]
            this._push<ColorCommand>({ type: 'C', easing: Easing.Linear, startTime: time, endTime: time, startR: r, startG: g, startB: b, endR: r, endG: g, endB: b })
        } else if (args.length === 8) {
            const [startTime, endTime, startR, startG, startB, endR, endG, endB] = args as [number, number, number, number, number, number, number, number]
            this._push<ColorCommand>({ type: 'C', easing: Easing.Linear, startTime, endTime, startR, startG, startB, endR, endG, endB })
        } else {
            const [easing, startTime, endTime, startR, startG, startB, endR, endG, endB] = args as [Easing, number, number, number, number, number, number, number, number]
            this._push<ColorCommand>({ type: 'C', easing, startTime, endTime, startR, startG, startB, endR, endG, endB })
        }
        return this
    }

    /** _P,H — Horizontal flip for the given time range */
    flipH(startTime: number, endTime: number): this {
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime, parameter: 'H' })
        return this
    }

    /** _P,V — Vertical flip for the given time range */
    flipV(startTime: number, endTime: number): this {
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime, parameter: 'V' })
        return this
    }

    /** _P,A — Additive blend mode for the given time range */
    additive(startTime: number, endTime: number): this {
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime, parameter: 'A' })
        return this
    }

    /**
     * _L — Loop group. Commands inside repeat `loopCount` times starting at `startTime`.
     * Times inside the callback are relative to the loop start (0 = first frame of the loop).
     *
     * @example
     * sprite('logo.png').loop(0, 4, l => {
     *   l.fade(Easing.Linear, 0, 500, 0, 1)
     *   l.fade(Easing.Linear, 500, 1000, 1, 0)
     * })
     */
    loop(startTime: number, loopCount: number, build: (l: LoopBuilder) => void): this {
        const lb = new LoopBuilder(startTime, loopCount)
        build(lb)
        if (lb._group.commands.length > 0) {
            this._sprite.loops.push(lb._group)
        }
        return this
    }

    // ── Build ───────────────────────────────────────────────────────────────────

    /** Returns the final StoryboardSprite. Called internally by the runtime. */
    build(): StoryboardSprite {
        return this._sprite
    }

    private _push<T extends Command>(cmd: T): void {
        this._sprite.commands.push(cmd)
    }
}

// ─── Script context ───────────────────────────────────────────────────────────

/**
 * The context object injected into every user script.
 * Exposes all the tools needed to build a storyboard.
 */
export interface ScriptContext {
    /** Create a new sprite and register it for rendering */
    sprite(filePath: string, layer?: Layer, origin?: Origin, x?: number, y?: number): SpriteBuilder
    /** BPM of the current beatmap (from project config) */
    bpm: number
    /** Audio offset in ms */
    offset: number
    /** Helpers to convert beats → ms */
    beat(beats: number): number
    /** Enums — available directly in scripts */
    Layer: typeof Layer
    Origin: typeof Origin
    Easing: typeof Easing
}

/**
 * Builds a ScriptContext that accumulates sprites into a shared array.
 * `scriptId` is used to namespace sprite IDs so sprites from different
 * scripts never collide in the renderer's sprite map.
 * The array is returned after the script runs.
 */
export function createScriptContext(scriptId: string, bpm: number, offset: number): {
    context: ScriptContext
    getSprites: () => StoryboardSprite[]
} {
    _idCounter = 0
    const sprites: StoryboardSprite[] = []
    const msPerBeat = bpm > 0 ? (60_000 / bpm) : 500

    const context: ScriptContext = {
        sprite(filePath, layer = Layer.Foreground, origin = Origin.Centre, x = 320, y = 240) {
            const builder = new SpriteBuilder(filePath, layer, origin, x, y)
            // Namespace the id so sprites from different scripts never share an id
            const sp = builder.build()
            sp.id = `${scriptId}::sprite_${_idCounter}`
            sprites.push(sp)
            // Return builder so the user can chain commands;
            // the sprite reference in the array stays in sync since it's the same object.
            return builder
        },
        bpm,
        offset,
        beat: (beats: number) => beats * msPerBeat + offset,
        Layer,
        Origin,
        Easing,
    }

    return {
        context,
        getSprites: () => sprites,
    }
}
