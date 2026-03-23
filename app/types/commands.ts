import { Easing } from './easing'

export type CommandType = 'F' | 'M' | 'MX' | 'MY' | 'S' | 'V' | 'R' | 'C' | 'P' | 'L' | 'T'

interface BaseCommand {
  type: CommandType
  easing: Easing
  startTime: number
  endTime: number
}

/** _F — Fade */
export interface FadeCommand extends BaseCommand {
  type: 'F'
  startOpacity: number
  endOpacity: number
}

/** _M — Move */
export interface MoveCommand extends BaseCommand {
  type: 'M'
  startX: number
  startY: number
  endX: number
  endY: number
}

/** _MX — Move X axis only */
export interface MoveXCommand extends BaseCommand {
  type: 'MX'
  startX: number
  endX: number
}

/** _MY — Move Y axis only */
export interface MoveYCommand extends BaseCommand {
  type: 'MY'
  startY: number
  endY: number
}

/** _S — Scale (uniform) */
export interface ScaleCommand extends BaseCommand {
  type: 'S'
  startScale: number
  endScale: number
}

/** _V — Vector scale (non-uniform) */
export interface VectorScaleCommand extends BaseCommand {
  type: 'V'
  startX: number
  startY: number
  endX: number
  endY: number
}

/** _R — Rotate */
export interface RotateCommand extends BaseCommand {
  type: 'R'
  startAngle: number
  endAngle: number
}

/** _C — Colour */
export interface ColorCommand extends BaseCommand {
  type: 'C'
  startR: number
  startG: number
  startB: number
  endR: number
  endG: number
  endB: number
}

/** _P — Parameter (flip H/V, additive blend) */
export interface ParameterCommand extends BaseCommand {
  type: 'P'
  parameter: 'H' | 'V' | 'A'
}

export type Command =
  | FadeCommand
  | MoveCommand
  | MoveXCommand
  | MoveYCommand
  | ScaleCommand
  | VectorScaleCommand
  | RotateCommand
  | ColorCommand
  | ParameterCommand
