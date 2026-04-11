import type { TextSpriteStyle } from '~/types'
import { TEXT_SPRITE_PREFIX } from '~/types'

const DEFAULT_STYLE: Required<TextSpriteStyle> = {
  font: 'Arial',
  size: 48,
  color: '#ffffff',
  bold: false,
  italic: false,
  strokeColor: '#000000',
  strokeWidth: 0,
  shadowBlur: 0,
  shadowColor: '#000000',
  shadowOffsetX: 0,
  shadowOffsetY: 0,
}

const mergeStyle = (style?: Partial<TextSpriteStyle>): Required<TextSpriteStyle> => ({
  ...DEFAULT_STYLE,
  ...style,
})

/** djb2 hash — returns an 8-char hex string. */
const djb2 = (str: string): string => {
  let hash = 5381
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) + hash) ^ str.charCodeAt(i)
    hash = hash >>> 0
  }
  return hash.toString(16).padStart(8, '0')
}

/** Returns the CSS font string for a given style. */
const fontString = (style: Required<TextSpriteStyle>): string => {
  const weight = style.bold ? 'bold' : 'normal'
  const slant = style.italic ? 'italic' : 'normal'
  return `${slant} ${weight} ${style.size}px ${style.font}`
}

/**
 * Returns a deterministic synthetic filePath key for a given char+style combination.
 * Format: `__text__:<hash8>`
 */
export const textCharKey = (char: string, style: Required<TextSpriteStyle>): string => {
  const hash = djb2(JSON.stringify({ char, style }))
  return `${TEXT_SPRITE_PREFIX}${hash}`
}

/** Shared measurement canvas — OffscreenCanvas works in both Workers and main thread. */
let _measureCtx: OffscreenCanvasRenderingContext2D | null = null

const getMeasureCtx = (): OffscreenCanvasRenderingContext2D => {
  if (!_measureCtx) {
    _measureCtx = new OffscreenCanvas(1, 1).getContext('2d')!
  }
  return _measureCtx
}

/**
 * Measures a character and returns two values:
 * - `advance`: how much the cursor should move to position the next character (pure glyph width)
 * - `canvasWidth`/`canvasHeight`: the actual pixel dimensions of the rasterized canvas
 *   (larger than advance due to stroke/shadow padding)
 */
export const measureChar = (
  char: string,
  style: Required<TextSpriteStyle>,
): { advance: number; canvasWidth: number; canvasHeight: number } => {
  const ctx = getMeasureCtx()
  ctx.font = fontString(style)

  const metrics = ctx.measureText(char)
  const advance = Math.ceil(metrics.width)
  const extraPad = style.strokeWidth + Math.max(0, style.shadowBlur) + 4

  return {
    advance,
    canvasWidth: Math.ceil(metrics.width + extraPad * 2),
    canvasHeight: Math.ceil(style.size + extraPad * 2),
  }
}

/**
 * Rasterizes a single character to an OffscreenCanvas with transparent background.
 * Works in both Web Workers and the main thread.
 */
export const rasterizeChar = (char: string, style: Required<TextSpriteStyle>): OffscreenCanvas => {
  const extraPad = style.strokeWidth + Math.max(0, style.shadowBlur) + 4
  const { canvasWidth, canvasHeight } = measureChar(char, style)

  const canvas = new OffscreenCanvas(canvasWidth, canvasHeight)
  const ctx = canvas.getContext('2d')!
  ctx.font = fontString(style)
  ctx.textBaseline = 'top'

  if (style.shadowBlur > 0) {
    ctx.shadowBlur = style.shadowBlur
    ctx.shadowColor = style.shadowColor
    ctx.shadowOffsetX = style.shadowOffsetX
    ctx.shadowOffsetY = style.shadowOffsetY
  }

  if (style.strokeWidth > 0) {
    ctx.strokeStyle = style.strokeColor
    ctx.lineWidth = style.strokeWidth * 2
    ctx.strokeText(char, extraPad, extraPad)
  }

  ctx.fillStyle = style.color
  ctx.fillText(char, extraPad, extraPad)

  return canvas
}

export { mergeStyle, DEFAULT_STYLE }
