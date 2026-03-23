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
