import { Easing } from '~/types/easing'

/**
 * Applies an osu! easing function to a normalized progress value.
 * @param easing  osu! easing enum value
 * @param t       normalized time in [0, 1]
 * @returns       eased value in [0, 1] (may briefly exceed bounds for elastic/back)
 */
export function applyEasing(easing: Easing, t: number): number {
  if (t <= 0) return 0
  if (t >= 1) return 1

  switch (easing) {
    case Easing.Linear:            return linear(t)
    case Easing.Out:               return quadOut(t)
    case Easing.In:                return quadIn(t)
    case Easing.QuadIn:            return quadIn(t)
    case Easing.QuadOut:           return quadOut(t)
    case Easing.QuadInOut:         return quadInOut(t)
    case Easing.CubicIn:           return cubicIn(t)
    case Easing.CubicOut:          return cubicOut(t)
    case Easing.CubicInOut:        return cubicInOut(t)
    case Easing.QuartIn:           return quartIn(t)
    case Easing.QuartOut:          return quartOut(t)
    case Easing.QuartInOut:        return quartInOut(t)
    case Easing.QuintIn:           return quintIn(t)
    case Easing.QuintOut:          return quintOut(t)
    case Easing.QuintInOut:        return quintInOut(t)
    case Easing.SineIn:            return sineIn(t)
    case Easing.SineOut:           return sineOut(t)
    case Easing.SineInOut:         return sineInOut(t)
    case Easing.ExpoIn:            return expoIn(t)
    case Easing.ExpoOut:           return expoOut(t)
    case Easing.ExpoInOut:         return expoInOut(t)
    case Easing.CircIn:            return circIn(t)
    case Easing.CircOut:           return circOut(t)
    case Easing.CircInOut:         return circInOut(t)
    case Easing.ElasticIn:         return elasticIn(t)
    case Easing.ElasticOut:        return elasticOut(t)
    case Easing.ElasticHalfOut:    return elasticHalfOut(t)
    case Easing.ElasticQuarterOut: return elasticQuarterOut(t)
    case Easing.ElasticInOut:      return elasticInOut(t)
    case Easing.BackIn:            return backIn(t)
    case Easing.BackOut:           return backOut(t)
    case Easing.BackInOut:         return backInOut(t)
    case Easing.BounceIn:          return bounceIn(t)
    case Easing.BounceOut:         return bounceOut(t)
    case Easing.BounceInOut:       return bounceInOut(t)
    default:                       return linear(t)
  }
}

/**
 * Linear interpolation between two values.
 */
export function lerp(start: number, end: number, t: number): number {
  return start + (end - start) * t
}

/**
 * Eased interpolation between two values.
 */
export function easedLerp(start: number, end: number, t: number, easing: Easing): number {
  return lerp(start, end, applyEasing(easing, t))
}

// ─── Easing implementations ─────────────────────────────────────────────────

const linear    = (t: number) => t

const quadIn    = (t: number) => t * t
const quadOut   = (t: number) => t * (2 - t)
const quadInOut = (t: number) => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t

const cubicIn    = (t: number) => t * t * t
const cubicOut   = (t: number) => --t * t * t + 1
const cubicInOut = (t: number) =>
  t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1

const quartIn    = (t: number) => t * t * t * t
const quartOut   = (t: number) => 1 - --t * t * t * t
const quartInOut = (t: number) => t < 0.5 ? 8 * t * t * t * t : 1 - 8 * --t * t * t * t

const quintIn    = (t: number) => t * t * t * t * t
const quintOut   = (t: number) => 1 + --t * t * t * t * t
const quintInOut = (t: number) =>
  t < 0.5 ? 16 * t * t * t * t * t : 1 + 16 * --t * t * t * t * t

const sineIn    = (t: number) => 1 - Math.cos((t * Math.PI) / 2)
const sineOut   = (t: number) => Math.sin((t * Math.PI) / 2)
const sineInOut = (t: number) => -(Math.cos(Math.PI * t) - 1) / 2

const expoIn    = (t: number) => Math.pow(2, 10 * (t - 1))
const expoOut   = (t: number) => 1 - Math.pow(2, -10 * t)
const expoInOut = (t: number) =>
  t < 0.5 ? Math.pow(2, 20 * t - 10) / 2 : (2 - Math.pow(2, -20 * t + 10)) / 2

const circIn    = (t: number) => 1 - Math.sqrt(1 - t * t)
const circOut   = (t: number) => Math.sqrt(1 - --t * t)
const circInOut = (t: number) =>
  t < 0.5
    ? (1 - Math.sqrt(1 - 4 * t * t)) / 2
    : (Math.sqrt(1 - (-2 * t + 2) ** 2) + 1) / 2

const C4 = (2 * Math.PI) / 3
const C5 = (2 * Math.PI) / 4.5

const elasticIn  = (t: number) =>
  -(Math.pow(2, 10 * t - 10) * Math.sin((t * 10 - 10.75) * C4))
const elasticOut = (t: number) =>
  Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * C4) + 1
const elasticHalfOut = (t: number) =>
  Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * C4 * 0.5) + 1
const elasticQuarterOut = (t: number) =>
  Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * C4 * 0.25) + 1
const elasticInOut = (t: number) =>
  t < 0.5
    ? -(Math.pow(2, 20 * t - 10) * Math.sin((20 * t - 11.125) * C5)) / 2
    : (Math.pow(2, -20 * t + 10) * Math.sin((20 * t - 11.125) * C5)) / 2 + 1

const C1 = 1.70158
const C2 = C1 * 1.525
const C3 = C1 + 1

const backIn    = (t: number) => C3 * t * t * t - C1 * t * t
const backOut   = (t: number) => 1 + C3 * Math.pow(t - 1, 3) + C1 * Math.pow(t - 1, 2)
const backInOut = (t: number) =>
  t < 0.5
    ? (Math.pow(2 * t, 2) * ((C2 + 1) * 2 * t - C2)) / 2
    : (Math.pow(2 * t - 2, 2) * ((C2 + 1) * (2 * t - 2) + C2) + 2) / 2

function bounceOut(t: number): number {
  const n1 = 7.5625
  const d1 = 2.75
  if (t < 1 / d1)        return n1 * t * t
  if (t < 2 / d1)        return n1 * (t -= 1.5 / d1) * t + 0.75
  if (t < 2.5 / d1)      return n1 * (t -= 2.25 / d1) * t + 0.9375
  return                         n1 * (t -= 2.625 / d1) * t + 0.984375
}

const bounceIn    = (t: number) => 1 - bounceOut(1 - t)
const bounceInOut = (t: number) =>
  t < 0.5 ? (1 - bounceOut(1 - 2 * t)) / 2 : (1 + bounceOut(2 * t - 1)) / 2
