/** Computed render state for a single sprite at a given timestamp */
export interface SpriteRenderState {
  spriteId: string
  x: number
  y: number
  scaleX: number
  scaleY: number
  rotation: number
  opacity: number
  r: number
  g: number
  b: number
  visible: boolean
  /** Additive blend mode (_P,A) */
  additive: boolean
  /** Horizontal flip (_P,H) */
  flipH: boolean
  /** Vertical flip (_P,V) */
  flipV: boolean
}
