// A wave of dots — a mesh deformed by two travelling sine waves.
//
// The thing no parameter set expresses: each dot needs its own phase, derived
// from where it sits in the grid, and its own brightness, derived from how
// steep the surface is under it. That is per-particle rules with access to the
// index, which is the whole reason scripts exist.

// A curved path is written as straight chords, so `segments` is the number
// that decides whether this reads as a wave or as a zigzag. Measured against
// the true curve: 10 segments leaves a 11.8px gap on a 46px amplitude — a
// quarter of the wave, and visible as corners. 18 leaves 3.8px, under the size
// of one dot. And `speed` under about 2 makes the surface barely move at all:
// measured, one dot travelled 11.8px across 1.3s at speed 1, and 70px at 2.5.

params({
    columns: { type: 'integer', default: 44, range: [4, 90] },
    rows: { type: 'integer', default: 13, range: [2, 30] },
    amplitude: { type: 'number', default: 46, range: [0, 200], unit: 'px' },
    cycles: { type: 'number', default: 1.7, range: [0.2, 6] },
    speed: { type: 'number', default: 2.5, range: [0.1, 8] },
    segments: { type: 'integer', default: 18, range: [2, 40] },
    tint: { type: 'color', default: '#3bff6a' },
    size: { type: 'number', default: 0.09, range: [0.01, 0.6] },
    depth: { type: 'number', default: 0.62, range: [0, 1] },
})

const columns = param('columns')
const rows = param('rows')
const amplitude = param('amplitude')
const cycles = param('cycles')
const speed = param('speed')
const segments = param('segments')
const size = param('size')
const depth = param('depth')

// A colour control arrives as { r, g, b } with channels already in 0-255 —
// the same range .color() wants, so there is nothing to convert.
const tint = param('tint')
const r = tint.r
const g = tint.g
const b = tint.b

// The mesh sits in the lower half, like the reference: the wave is a surface
// the viewer looks ACROSS, not a field they look at head on.
const left = -60
const right = 800
const near = 470   // the front row, at the bottom of the frame
const far = 250   // the back row, receding upward

// The surface height at (u, v) at a moment.
//
// Two waves crossing at an angle is what stops it reading as corrugated iron:
// one alone gives parallel ridges, and the interference is what makes it look
// like cloth.
const height = (u, v, t) => {
    const a = Math.sin((u * cycles + t) * Math.PI * 2)
    const c = Math.sin((u * cycles * 0.6 - v * 1.3 + t * 0.8) * Math.PI * 2)
    return (a * 0.65 + c * 0.35) * amplitude
}

for (let row = 0; row < rows; row++) {
    // v: 0 at the front, 1 at the back.
    const v = rows === 1 ? 0 : row / (rows - 1)

    // Perspective. Rows further back are narrower, closer together and dimmer —
    // three cues from one number, which is what sells depth without any 3D.
    const shrink = 1 - depth * v * 0.55
    const y = near + (far - near) * Math.pow(v, 0.72)
    const dim = 1 - depth * v * 0.7

    for (let col = 0; col < columns; col++) {
        const u = columns === 1 ? 0 : col / (columns - 1)

        // The row is narrowed about the centre of the frame.
        const centre = 320
        const x = centre + (left + (right - left) * u - centre) * shrink

        const dot = sprite(Image.glow).at(x, y)

        // A curved path costs one command per segment, so it is worth counting:
        // this is the whole cost of the effect.
        for (let s = 0; s < segments; s++) {
            const t0 = (s / segments) * duration
            const t1 = ((s + 1) / segments) * duration
            const h0 = height(u, v, (t0 / duration) * speed)
            const h1 = height(u, v, (t1 / duration) * speed)

            dot.moveY(t0, t1, y + h0, y + h1)
        }

        // Brightness follows the SLOPE, not the height: what catches the eye on a
        // real wave is the crest turning over, and that is where the surface is
        // steepest. Sampled once, at the middle of the clip.
        const mid = 0.5 * speed
        const slope = Math.abs(
            height(u + 0.02, v, mid) - height(u - 0.02, v, mid),
        ) / Math.max(amplitude, 1)
        const lift = Math.min(1, 0.35 + slope * 9)

        dot.fade(0, 1, 0, lift * dim)
            .fade(duration - 1, duration, lift * dim, 0)
            .scale(0, 1, size * shrink, size * shrink)
            .color(0, 1, r * lift, g * lift, b * lift, r * lift, g * lift, b * lift)
            .additive(0, duration)
    }
}

console.log(columns * rows + ' dots, ' + (columns * rows * (segments + 5)) + ' commands')
