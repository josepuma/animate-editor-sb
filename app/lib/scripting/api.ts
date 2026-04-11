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
    TextSpriteStyle,
    TextSpriteMap,
} from '~/types'
import { textCharKey, measureChar, mergeStyle } from '~/lib/scripting/textRasterizer'
import type { Color, GradientStep } from '~/types/color'
import { hex, hsl } from '~/types/color'

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

    // flipH(time)
    flipH(time: number): this
    // flipH(startTime, endTime)
    flipH(startTime: number, endTime: number): this
    flipH(startTime: number, endTime?: number): this {
        const end = endTime ?? startTime
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime: end, parameter: 'H' })
        return this
    }

    // flipV(time)
    flipV(time: number): this
    // flipV(startTime, endTime)
    flipV(startTime: number, endTime: number): this
    flipV(startTime: number, endTime?: number): this {
        const end = endTime ?? startTime
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime: end, parameter: 'V' })
        return this
    }

    // additive(time)
    additive(time: number): this
    // additive(startTime, endTime)
    additive(startTime: number, endTime: number): this
    additive(startTime: number, endTime?: number): this {
        const end = endTime ?? startTime
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime: end, parameter: 'A' })
        return this
    }

    private _push<T extends Command>(cmd: T): void {
        this._group.commands.push(cmd)
    }
}

// ─── SpriteBuilder ────────────────────────────────────────────────────────────

let _idCounter = 0

export class SpriteBuilder {
    readonly _sprite: StoryboardSprite

    /** Image width in pixels (0 if dimensions unknown) */
    readonly width: number
    /** Image height in pixels (0 if dimensions unknown) */
    readonly height: number
    /** Default X position of this sprite */
    get defaultX(): number { return this._sprite.defaultX }
    /** Default Y position of this sprite */
    get defaultY(): number { return this._sprite.defaultY }

    constructor(filePath: string, layer: Layer, origin: Origin, x = 320, y = 240, imgWidth = 0, imgHeight = 0) {
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
        this.width = imgWidth
        this.height = imgHeight
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
    // flipH(time)
    flipH(time: number): this
    // flipH(startTime, endTime)
    flipH(startTime: number, endTime: number): this
    flipH(startTime: number, endTime?: number): this {
        const end = endTime ?? startTime
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime: end, parameter: 'H' })
        return this
    }

    /** _P,V — Vertical flip for the given time range */
    // flipV(time)
    flipV(time: number): this
    // flipV(startTime, endTime)
    flipV(startTime: number, endTime: number): this
    flipV(startTime: number, endTime?: number): this {
        const end = endTime ?? startTime
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime: end, parameter: 'V' })
        return this
    }

    /** _P,A — Additive blend mode for the given time range */
    // additive(time)
    additive(time: number): this
    // additive(startTime, endTime)
    additive(startTime: number, endTime: number): this
    additive(startTime: number, endTime?: number): this {
        const end = endTime ?? startTime
        this._push<ParameterCommand>({ type: 'P', easing: Easing.Linear, startTime, endTime: end, parameter: 'A' })
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

// ─── TextBuilder ─────────────────────────────────────────────────────────────

/**
 * A SpriteBuilder for a single rasterized character.
 * Behaves exactly like SpriteBuilder — supports all commands (fade, move, scale, etc.).
 * The filePath is a synthetic `__text__:<hash>` key resolved at render/export time.
 */
export class TextBuilder extends SpriteBuilder {
    constructor(key: string, layer: Layer, origin: Origin, x: number, y: number, charWidth: number, charHeight: number) {
        super(key, layer, origin, x, y, charWidth, charHeight)
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
    /**
     * Rasterizes a single character into a SpriteBuilder.
     * Returns null for whitespace characters.
     * Use `.width` / `.height` on the returned builder for layout calculations.
     */
    text(content: string, style: Partial<TextSpriteStyle>, layer?: Layer, origin?: Origin, x?: number, y?: number): TextBuilder
    text(content: string, layer?: Layer, origin?: Origin, x?: number, y?: number): TextBuilder
    /** BPM of the current beatmap (from project config) */
    bpm: number
    /** Audio offset in ms */
    offset: number
    /** Helpers to convert beats → ms */
    beat(beats: number): number
    /** Random float in [min, max) */
    random(min: number, max: number): number
    /** Random integer in [min, max] (inclusive) */
    randomInt(min: number, max: number): number
    /** Converts a hex color string (#RGB or #RRGGBB) to a Color object */
    hex(value: string): Color
    /** Converts HSL values (h: 0-360, s: 0-100, l: 0-100) to a Color object */
    hsl(h: number, s: number, l: number): Color
    /** * Returns a random color by interpolating through a list of gradient steps.
     * @param steps Array of {pos, color} where pos is 0.0 to 1.0
     */
    randomGradientColor(steps: GradientStep[]): Color
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
export function createScriptContext(
    scriptId: string,
    bpm: number,
    offset: number,
    imageDimensions: Record<string, { width: number; height: number }> = {},
): {
    context: ScriptContext
    getSprites: () => StoryboardSprite[]
    getTextSprites: () => TextSpriteMap
} {
    _idCounter = 0
    const sprites: StoryboardSprite[] = []
    const textSprites: TextSpriteMap = {}
    const msPerBeat = bpm > 0 ? (60_000 / bpm) : 500

    const context: ScriptContext = {
        sprite(filePath, layer = Layer.Foreground, origin = Origin.Centre, x = 320, y = 240) {
            const dims = imageDimensions[filePath]
            const builder = new SpriteBuilder(filePath, layer, origin, x, y, dims?.width ?? 0, dims?.height ?? 0)
            // Namespace the id so sprites from different scripts never share an id
            const sp = builder.build()
            sp.id = `${scriptId}::sprite_${_idCounter}`
            sprites.push(sp)
            // Return builder so the user can chain commands;
            // the sprite reference in the array stays in sync since it's the same object.
            return builder
        },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        text(content: string, ...args: any[]): TextBuilder {
            // Overload resolution:
            //   text(content, style, layer?, origin?, x?, y?)
            //   text(content, layer?,  origin?, x?, y?)
            let resolvedStyle: Partial<TextSpriteStyle> | undefined
            let resolvedLayer: Layer = Layer.Foreground
            let resolvedOrigin: Origin = Origin.Centre
            let resolvedX = 320
            let resolvedY = 240

            if (args.length > 0 && args[0] !== undefined && typeof args[0] === 'object') {
                resolvedStyle = args[0]
                resolvedLayer  = args[1] ?? Layer.Foreground
                resolvedOrigin = args[2] ?? Origin.Centre
                resolvedX      = args[3] ?? 320
                resolvedY      = args[4] ?? 240
            } else {
                resolvedLayer  = args[0] ?? Layer.Foreground
                resolvedOrigin = args[1] ?? Origin.Centre
                resolvedX      = args[2] ?? 320
                resolvedY      = args[3] ?? 240
            }

            // Use the first character of the string (or a space if empty)
            const char = content[0] ?? ' '

            const merged = mergeStyle(resolvedStyle)
            const key = textCharKey(char, merged)
            if (!textSprites[key]) textSprites[key] = { char, style: merged }

            const { canvasWidth, canvasHeight } = measureChar(char, merged)
            const builder = new TextBuilder(key, resolvedLayer, resolvedOrigin, resolvedX, resolvedY, canvasWidth, canvasHeight)
            builder._sprite.id = `${scriptId}::text_${++_idCounter}`
            sprites.push(builder._sprite)
            return builder
        },
        bpm,
        offset,
        beat: (beats: number) => beats * msPerBeat + offset,
        random: (min: number, max: number) => Math.random() * (max - min) + min,
        randomInt: (min: number, max: number) => Math.floor(Math.random() * (max - min + 1)) + min,
        hex,
        hsl,
        randomGradientColor: (steps: GradientStep[]): Color => {
            // 1. Verificación de seguridad y extracción del primer elemento
            const firstStep = steps[0];

            if (!firstStep) {
                // Si el array está vacío, devolvemos blanco
                return { r: 255, g: 255, b: 255 };
            }

            if (steps.length === 1) {
                return firstStep.color;
            }

            // 2. Ordenar
            const sorted = [...steps].sort((a, b) => a.pos - b.pos);
            const t = Math.random();

            // 3. Referencias seguras (ya validamos que hay al menos uno)
            const first = sorted[0]!; // El "!" le dice a TS: "Confía en mí, no es nulo"
            const last = sorted[sorted.length - 1]!;

            if (t <= first.pos) return first.color;
            if (t >= last.pos) return last.color;

            for (let i = 0; i < sorted.length - 1; i++) {
                const start = sorted[i]!;
                const end = sorted[i + 1]!;

                if (t >= start.pos && t <= end.pos) {
                    const localT = (t - start.pos) / (end.pos - start.pos);

                    return {
                        r: Math.round(start.color.r + (end.color.r - start.color.r) * localT),
                        g: Math.round(start.color.g + (end.color.g - start.color.g) * localT),
                        b: Math.round(start.color.b + (end.color.b - start.color.b) * localT)
                    };
                }
            }

            return first.color;
        },
        Layer,
        Origin,
        Easing
    }

    return {
        context,
        getSprites: () => sprites,
        getTextSprites: () => textSprites,
    }
}
