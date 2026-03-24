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

    fade(easing: Easing, startTime: number, endTime: number, startOpacity: number, endOpacity: number): this {
        this._push<FadeCommand>({ type: 'F', easing, startTime, endTime, startOpacity, endOpacity })
        return this
    }

    move(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this {
        this._push<MoveCommand>({ type: 'M', easing, startTime, endTime, startX, startY, endX, endY })
        return this
    }

    moveX(easing: Easing, startTime: number, endTime: number, startX: number, endX: number): this {
        this._push<MoveXCommand>({ type: 'MX', easing, startTime, endTime, startX, endX })
        return this
    }

    moveY(easing: Easing, startTime: number, endTime: number, startY: number, endY: number): this {
        this._push<MoveYCommand>({ type: 'MY', easing, startTime, endTime, startY, endY })
        return this
    }

    scale(easing: Easing, startTime: number, endTime: number, startScale: number, endScale: number): this {
        this._push<ScaleCommand>({ type: 'S', easing, startTime, endTime, startScale, endScale })
        return this
    }

    scaleVec(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this {
        this._push<VectorScaleCommand>({ type: 'V', easing, startTime, endTime, startX, startY, endX, endY })
        return this
    }

    rotate(easing: Easing, startTime: number, endTime: number, startAngle: number, endAngle: number): this {
        this._push<RotateCommand>({ type: 'R', easing, startTime, endTime, startAngle, endAngle })
        return this
    }

    color(easing: Easing, startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this {
        this._push<ColorCommand>({ type: 'C', easing, startTime, endTime, startR, startG, startB, endR, endG, endB })
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
    fade(easing: Easing, startTime: number, endTime: number, startOpacity: number, endOpacity: number): this {
        this._push<FadeCommand>({ type: 'F', easing, startTime, endTime, startOpacity, endOpacity })
        return this
    }

    /** _M — Move (both axes) */
    move(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this {
        this._push<MoveCommand>({ type: 'M', easing, startTime, endTime, startX, startY, endX, endY })
        return this
    }

    /** _MX — Move X axis only */
    moveX(easing: Easing, startTime: number, endTime: number, startX: number, endX: number): this {
        this._push<MoveXCommand>({ type: 'MX', easing, startTime, endTime, startX, endX })
        return this
    }

    /** _MY — Move Y axis only */
    moveY(easing: Easing, startTime: number, endTime: number, startY: number, endY: number): this {
        this._push<MoveYCommand>({ type: 'MY', easing, startTime, endTime, startY, endY })
        return this
    }

    /** _S — Uniform scale */
    scale(easing: Easing, startTime: number, endTime: number, startScale: number, endScale: number): this {
        this._push<ScaleCommand>({ type: 'S', easing, startTime, endTime, startScale, endScale })
        return this
    }

    /** _V — Vector (non-uniform) scale */
    scaleVec(easing: Easing, startTime: number, endTime: number, startX: number, startY: number, endX: number, endY: number): this {
        this._push<VectorScaleCommand>({ type: 'V', easing, startTime, endTime, startX, startY, endX, endY })
        return this
    }

    /** _R — Rotate (radians) */
    rotate(easing: Easing, startTime: number, endTime: number, startAngle: number, endAngle: number): this {
        this._push<RotateCommand>({ type: 'R', easing, startTime, endTime, startAngle, endAngle })
        return this
    }

    /** _C — Colour tint (0–255 per channel) */
    color(easing: Easing, startTime: number, endTime: number, startR: number, startG: number, startB: number, endR: number, endG: number, endB: number): this {
        this._push<ColorCommand>({ type: 'C', easing, startTime, endTime, startR, startG, startB, endR, endG, endB })
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
