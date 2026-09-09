// An aurora — curtains of light seen from a distance.
//
// The version this replaces got the idea right and the execution wrong, and the
// difference is worth writing down because it is all in what an aurora looks
// like rather than in any number:
//
//   1. **The curtain is curved, not vertical.** Straight columns read as a
//      barcode however they ripple. A real curtain hangs in an arc and leans,
//      so a column's own angle depends on where it sits along that arc.
//   2. **Colour changes along a column, not between columns.** Green at the
//      base going violet at the crown is the whole palette of the thing; a
//      column of one flat colour is a coloured bar.
//   3. **It is fog, not bars.** Every column is drawn twice — a soft `streak`
//      for the shaft and a wide `smoke` for the haze around it. The haze is
//      what removes the hard edges, and hard edges were the whole complaint.
//
// Seen from a distance, which is the last piece: low contrast, lots of overlap,
// and nothing in sharp focus.

params({
    columns: { type: 'integer', default: 70, range: [6, 160] },

    // How far a column can tilt off vertical.
    //
    // **Small on purpose.** The previous version fanned 34° with a 12° lean,
    // and measured that gave angles from -5° to +29° with 84% of columns
    // leaning the same way — a set of parallel diagonal streaks, which is the
    // barcode rotated. In the reference the shafts are nearly upright; what
    // reads as a hanging curtain is the **base** undulating, below.
    tilt: { type: 'number', default: 7, range: [0, 40], unit: '°' },

    // How much the bottom edge of the curtain undulates.
    //
    // This is the shape, and it is what the arc was reaching for and missing:
    // a curtain hangs in folds, so its lower hem rises and falls across the
    // frame while the light still falls straight down.
    hem: { type: 'number', default: 70, range: [0, 200], unit: 'px' },
    // How many folds fit across it. Around two reads as cloth; higher and it
    // is a frill.
    folds: { type: 'number', default: 2.2, range: [0.5, 6] },

    baseline: { type: 'number', default: 330, range: [0, 480], unit: 'px' },
    height: { type: 'number', default: 300, range: [40, 600], unit: 'px' },
    // Adjacent columns differ in height, so the top edge is ragged. A level
    // top edge is a wall.
    ragged: { type: 'number', default: 0.45, range: [0, 1] },

    width: { type: 'number', default: 760, range: [200, 1400], unit: 'px' },
    sway: { type: 'number', default: 6, range: [0, 60], unit: 'px' },
    ripples: { type: 'number', default: 1.4, range: [0.2, 6] },
    speed: { type: 'number', default: 0.9, range: [0.1, 6] },
    segments: { type: 'integer', default: 12, range: [2, 40] },

    // Three, because an aurora is not two colours meeting: it is green low
    // down, going teal, going violet at the crown, with the transition
    // happening *along* each column.
    base: { type: 'color', default: '#37e08a' },
    mid: { type: 'color', default: '#48d8e0' },
    crown: { type: 'color', default: '#9d5cf0' },

    // Deliberately low. Additive stacking with this much overlap reaches white
    // fast, and a blown-out sheet loses the colour that makes it an aurora.
    opacity: { type: 'number', default: 0.16, range: [0.01, 1] },
    thickness: { type: 'number', default: 0.5, range: [0.05, 3] },
    // The haze around each shaft, as a multiple of the shaft's width. This is
    // what turns bars into fog.
    haze: { type: 'number', default: 3.4, range: [1, 8] },
})

const columns = param('columns')
const tilt = param('tilt')
const hem = param('hem')
const folds = param('folds')
const baseline = param('baseline')
const curtainHeight = param('height')
const ragged = param('ragged')
const curtainWidth = param('width')
const sway = param('sway')
const ripples = param('ripples')
const speed = param('speed')
const segments = param('segments')
const opacity = param('opacity')
const thickness = param('thickness')
const haze = param('haze')
const base = param('base')
const mid = param('mid')
const crown = param('crown')

// The built-in shapes are drawn at 64 points, so a scale is the size wanted
// over that. This project has twice been bitten by assuming otherwise — the
// texture pack is 512, so the same scale gives eight times the size.
const SOURCE = 64
const centre = 320
const left = centre - curtainWidth / 2

// How far the hem hangs at a point across the curtain, in the range -1…1.
//
// Two waves, so the folds are uneven: one alone gives a scalloped edge like a
// lampshade, and what a curtain does is hang in folds of different depths.
const hemAt = (u) => {
    const a = Math.sin(u * folds * Math.PI * 2)
    const c = Math.sin(u * folds * 0.37 * Math.PI * 2 + 1.7)
    return a * 0.62 + c * 0.38
}

// A column's own tilt: it follows the **slope of the hem**, so a shaft standing
// on a rising fold leans with it.
//
// Derived rather than fanned, and that is the fix: an angle that came from the
// column's position gave a parallel diagonal comb, while an angle that comes
// from the surface under it is upright where the hem is level and tilted where
// the hem climbs — which is what the eye reads as cloth.
const angleAt = (u) => {
    const step = 0.02
    const slope = (hemAt(u + step) - hemAt(u - step)) / (step * 2)
    return tilt * Math.max(-1, Math.min(1, slope / 6))
}

// The ripple: two waves at different rates, so the sheet moves like cloth
// rather than swaying as one slab.
const rippleAt = (u, t) => {
    const a = Math.sin((u * ripples + t) * Math.PI * 2)
    const c = Math.sin((u * ripples * 0.43 - t * 0.61) * Math.PI * 2)
    return a * 0.7 + c * 0.3
}

// Three-stop colour ramp: base → mid → crown.
const colourAt = (v) => {
    if (v < 0.5) {
        const k = v * 2
        return {
            r: base.r + (mid.r - base.r) * k,
            g: base.g + (mid.g - base.g) * k,
            b: base.b + (mid.b - base.b) * k,
        }
    }
    const k = (v - 0.5) * 2
    return {
        r: mid.r + (crown.r - mid.r) * k,
        g: mid.g + (crown.g - mid.g) * k,
        b: mid.b + (crown.b - mid.b) * k,
    }
}

// Each column is drawn as a stack of short pieces rather than one tall streak.
//
// That is what lets the colour change *along* it: a sprite carries one tint,
// so a gradient up a column has to be several sprites. Three is enough to
// read as a ramp and cheap enough to afford at this column count.
const PIECES = 3

for (let col = 0; col < columns; col++) {
    const u = columns === 1 ? 0 : col / (columns - 1)
    const x = left + curtainWidth * u

    // The hem: where this column stands. The bottom edge undulating is the
    // curtain shape, and it is what the fanned arc was standing in for.
    const columnBase = baseline + hemAt(u) * hem
    const angle = angleAt(u)

    // Ragged tops: a level top edge is a wall, not a curtain. Derived from the
    // column index rather than random, so it is the same every evaluation —
    // the preview and the exported file have to agree.
    const raggedness = 1 - ragged * (0.5 + 0.5 * Math.sin(u * 37.7))
    const columnHeight = curtainHeight * raggedness

    const pieceHeight = columnHeight / PIECES

    for (let piece = 0; piece < PIECES; piece++) {
        // v: 0 at the base of the column, 1 at its crown.
        const v = PIECES === 1 ? 0 : piece / (PIECES - 1)
        const tint = colourAt(v)

        // Higher pieces are fainter: an aurora's crown fades into the sky
        // rather than ending.
        const pieceFade = 1 - v * 0.55

        const pieceY = columnBase - pieceHeight * (piece + 0.5)

        // Two sprites per piece: the shaft, and the haze around it.
        //
        // The haze is the whole reason this reads as fog rather than as bars.
        // Drawn first so it sits behind, wider and fainter.
        const layers = [
            { image: Image.smoke, width: thickness * haze, alpha: 0.5 },
            { image: Image.streak, width: thickness, alpha: 1 },
        ]

        for (const layer of layers) {
            const shaft = sprite(layer.image, Layer.Background)
                .at(x, pieceY)
                .additive(0, duration)
                .color(0, 0, tint.r, tint.g, tint.b, tint.r, tint.g, tint.b)
                // The column's own angle — the arc made visible.
                .rotate(0, duration, (angle * Math.PI) / 180, (angle * Math.PI) / 180)

            for (let s = 0; s < segments; s++) {
                const t0 = (s / segments) * duration
                const t1 = ((s + 1) / segments) * duration
                const p0 = (t0 / duration) * speed
                const p1 = ((t1 / duration)) * speed

                const r0 = rippleAt(u, p0)
                const r1 = rippleAt(u, p1)

                shaft.move(
                    Ease.sineInOut, t0, t1,
                    x + r0 * sway, pieceY - r0 * pieceHeight * 0.12,
                    x + r1 * sway, pieceY - r1 * pieceHeight * 0.12,
                )

                // Height rides the ripple, so light climbs where the sheet
                // bulges. `scaleVec` because the axes differ by design.
                const h0 = (pieceHeight * 1.6 * (1 + r0 * 0.22)) / SOURCE
                const h1 = (pieceHeight * 1.6 * (1 + r1 * 0.22)) / SOURCE
                shaft.scaleVec(
                    Ease.sineInOut, t0, t1,
                    layer.width, h0, layer.width, h1,
                )
            }

            // Brightness ripples on its own slower period, so light appears
            // and dies in place while the curtain drifts.
            const glowSteps = Math.max(2, Math.floor(segments / 2))
            for (let s = 0; s < glowSteps; s++) {
                const t0 = (s / glowSteps) * duration
                const t1 = ((s + 1) / glowSteps) * duration
                const lit = (t) => {
                    const q = Math.sin((u * ripples * 0.8 - t * 0.44) * Math.PI * 2)
                    // Never fully dark: a column that vanishes leaves a hole,
                    // and the sheet is the effect.
                    return opacity * pieceFade * layer.alpha * (0.4 + 0.6 * (q * 0.5 + 0.5))
                }
                shaft.fade(
                    Ease.sineInOut, t0, t1,
                    lit((t0 / duration) * speed),
                    lit((t1 / duration) * speed),
                )
            }
        }
    }
}
