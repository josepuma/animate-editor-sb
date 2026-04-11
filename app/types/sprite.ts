import { Layer, Origin } from './layer'
import type { Command } from './commands'

/** One L block from a .osb file — commands use times relative to the loop start. */
export interface LoopGroup {
  startTime: number
  loopCount: number
  commands: Command[]
}

export interface StoryboardSprite {
  id: string
  layer: Layer
  origin: Origin
  /** Path relative to the project root */
  filePath: string
  defaultX: number
  defaultY: number
  commands: Command[]
  loops: LoopGroup[]
}

/** Prefix used in filePath to identify text/character sprites generated at runtime. */
export const TEXT_SPRITE_PREFIX = '__text__:'

export interface TextSpriteStyle {
  /** Font family name (default: 'Arial') */
  font?: string
  /** Font size in pixels (default: 48) */
  size?: number
  /** CSS color string (default: '#ffffff') */
  color?: string
  bold?: boolean
  italic?: boolean
  strokeColor?: string
  /** Stroke width in pixels (default: 0) */
  strokeWidth?: number
  shadowBlur?: number
  shadowColor?: string
  shadowOffsetX?: number
  shadowOffsetY?: number
}

export interface TextCharDefinition {
  char: string
  /** Fully merged style — no partial values */
  style: TextSpriteStyle
}

/** Maps synthetic filePath keys (`__text__:<hash>`) to their char+style definition. */
export type TextSpriteMap = Record<string, TextCharDefinition>
