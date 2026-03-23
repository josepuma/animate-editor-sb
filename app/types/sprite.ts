import { Layer, Origin } from './layer'
import type { Command } from './commands'

export interface StoryboardSprite {
  id: string
  layer: Layer
  origin: Origin
  /** Path relative to the project root */
  filePath: string
  defaultX: number
  defaultY: number
  commands: Command[]
}
