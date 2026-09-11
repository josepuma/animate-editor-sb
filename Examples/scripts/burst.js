// "MAYBE WE'LL SHINE FOREVER" — the charge before the final chorus.
//
// A crescendo has a **shape in time**, and that is the whole effect. Two earlier
// versions of this file missed it in opposite directions and failed the same
// way: measured, the ported original held 287 particles alive for three and a
// half seconds, and the tunnel rewrite held 364. Both are a *flow*, and a flow
// cannot break — it can only stop. What reads as a burst is the difference
// between before and after.
//
// So the clip is three acts, and their boundaries are parameters because they
// have to land on the music:
//
//   ┌─────────── charge ───────────┬─ burst ─┬──── shine ────┐
//   sparse, slow, gathering inward  everything  streaks flying
//   tightening as it goes           at once     outward, calm
//
// Four rules carry it, and none of them is a number:
//
//   1. **Inward, not outward.** Energy converging is what a charge looks like.
//      The tunnel rewrite sent everything outward from the first frame, which
//      reads as an explosion that already happened — no build, nothing to wait
//      for. That was the wrong effect, well made.
//   2. **Density ramps.** Particles per second rises across the charge, so the
//      screen fills as the music does. A constant rate reads as a machine.
//   3. **The burst is a discontinuity.** One volley, all at once, from the
//      centre outward. Anything gradual there is a crescendo that fizzles.
//   4. **Additive builds white by accumulation.** Every particle is dim; the hot
//      core is where they pile up. Declaring white throws the palette away —
//      measured on the first port: ink 1.35× the stage and a blown disc where
//      four colours should have been.

params({
    // Where the charge breaks, as a fraction of the clip. Put the clip's start
    // on the build and this on the downbeat.
    burstAt: { type: 'number', default: 0.62, range: [0.15, 0.9] },

    // How many particles the charge throws inward in total. Not a rate: every
    // particle is a sprite whose whole life is baked as text, so this is a hard
    // budget rather than a dial.
    charge: { type: 'integer', default: 900, range: [40, 1400] },
    // How many go out in the burst itself. Fewer than the charge, larger and
    // brighter — a burst is read by its size, not its count.
    burst: { type: 'integer', default: 420, range: [20, 700] },

    // How much faster particles arrive at the end of the charge than at the
    // start. This is the crescendo: 1 is a flat rate, and flat is a machine.
    ramp: { type: 'number', default: 2.6, range: [1, 12] },

    centreX: { type: 'number', default: 320, range: [-107, 747], unit: 'px' },
    centreY: { type: 'number', default: 240, range: [0, 480], unit: 'px' },

    // How far out the charge starts. Past the frame on purpose: particles that
    // begin on screen are particles the eye watches appear.
    reach: { type: 'number', default: 520, range: [200, 900], unit: 'px' },

    // Cool where it gathers, hot where it lands. Read from distance rather than
    // drawn at random — a ramp picked per particle exists in the file and never
    // on screen, which is what the first port did with its four colours.
    outerColour: { type: 'color', default: '#8d3f16' },
    midColour: { type: 'color', default: '#ffa631' },
    coreColour: { type: 'color', default: '#fdfce5' },

    // Low on purpose. At 0.8 the second overlapping particle is already white
    // and the ramp never reads; here several have to stack to reach white, and
    // that stacking is what draws the core.
    opacity: { type: 'number', default: 0.55, range: [0.02, 1] },

    // How far a streak stretches along its travel. Multiplies a scale that is
    // already applied, so the base thickness stays small — getting this wrong
    // is how this project once shipped 4000px streaks.
    stretch: { type: 'number', default: 11, range: [1, 24] },
})

const burstAt = param('burstAt')
const chargeCount = param('charge')
const burstCount = param('burst')
const ramp = param('ramp')
const centre = { x: param('centreX'), y: param('centreY') }
const reach = param('reach')
const baseOpacity = param('opacity')
const stretch = param('stretch')

const outerColour = param('outerColour')
const midColour = param('midColour')
const coreColour = param('coreColour')

// Measured peak alpha per file, because brightness decides how many of a thing
// you need and the filename says nothing:
//
//   stem.png        peak 255, mean 56   ← the only bright file in the pack
//   circle_blur.png peak 230            ← a filled disc
//   star.png        peak 112
//   line.png        peak  35, mean  1   ← 14% brightness
//   round-blur.png  peak  16            ← a dim hoop, and a hoop
//
// The first port got away with `line.png` by stacking 596 of them and letting
// accumulation do the work. Anything with fewer particles has to start bright.
const STREAK = 'sb/stem.png'
const STREAK_THIN = 'sb/line.png'
const GLOW = 'sb/circle_blur.png'
const FLARE = 'sb/starflare.jpg'
const STAR = 'sb/star.png'

const SOURCE = 250
const STAR_SOURCE = 134

const burstTime = duration * burstAt

/**
 * @param {{r: number, g: number, b: number}} a
 * @param {{r: number, g: number, b: number}} b
 * @param {number} t
 */
const mix = (a, b, t) => ({
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
})

/**
 * The palette as one ramp: hot at the centre, cool at the rim.
 * @param {number} t 0 at the centre, 1 at the edge.
 */
const rampAt = (t) => t < 0.5
    ? mix(coreColour, midColour, t * 2)
    : mix(midColour, outerColour, (t - 0.5) * 2)

// ---------------------------------------------------------------------------
// Act one — the charge.
//
// Streaks fly inward from beyond the frame, arriving faster and faster. Every
// one lands *at* the burst rather than whenever its own life ends, so the whole
// field converges on a single instant. That convergence is the crescendo: the
// screen does not merely fill, it fills toward a point in time.
// ---------------------------------------------------------------------------

const charge = () => {
    for (let i = 0; i < chargeCount; i += 1) {
        const p = i / chargeCount

        // Birth times bunch toward the end. Squaring the position is what turns
        // a steady rate into a build — at ramp 7 the last fifth of the charge
        // carries roughly half the particles.
        // The birth time is what the ramp shapes, and the first version of this
        // computed it and then **threw it away** — every particle landed at the
        // burst and worked backwards by its own travel time, so nothing could
        // be born earlier than `burst − maxLife`. Measured: not one particle
        // born between 400ms and 2000ms of a six-second clip, with the first
        // 40% of the screen empty. The ramp was not too steep; it was unused.
        const born = burstTime * (1 - Math.pow(1 - p, ramp))

        // Travel time shortens as the charge tightens. That is what actually
        // accelerates a crescendo: not only more particles, but each one
        // crossing faster than the last.
        const travel = rng.between(900, 1500) * (1 - p * 0.55)

        // Arrival is staggered slightly rather than exact: every streak landing
        // on the same millisecond reads as a shutter, not as a gathering.
        const land = Math.min(burstTime - rng.between(0, 140), born + travel)
        if (land <= born) continue
        const life = land - born

        const angle = rng.unit() * Math.PI * 2
        const distance = reach * rng.between(0.75, 1.25)
        const fromX = centre.x + Math.cos(angle) * distance
        const fromY = centre.y + Math.sin(angle) * distance * 0.72

        // Late arrivals are brighter and fatter — the charge intensifies in
        // what each particle *is*, not only in how many there are.
        const heat = 0.55 + p * 0.75
        const thickness = (rng.between(4, 11) / SOURCE) * heat
        const length = thickness * stretch * rng.between(0.7, 1.3)

        const colour = rampAt(rng.between(0.3, 1) * (1 - p * 0.5))
        const opacity = baseOpacity * heat

        sprite(rng.unit() < 0.7 ? STREAK : STREAK_THIN, { origin: Origin.Centre })
            .fade(Ease.quadOut, born, born + life * 0.3, 0, opacity)
            // Held to the landing, then cut: a streak that fades out before it
            // arrives is a streak that never arrives.
            .fade(land - 60, land, opacity, 0)
            // quadIn — approaching accelerates. Linear is the single most
            // reliable way to make motion look computed.
            .move(Ease.quadIn, born, land, fromX, fromY, centre.x, centre.y)
            .scaleVec(Ease.quadIn, born, land, length * 0.4, thickness * 0.6, length, thickness)
            // Aligned to its own spoke: a streak drawn pointing right and
            // launched in all directions otherwise faces where it was drawn.
            .rotate(born, born, angle, angle)
            .color(born, born, colour.r, colour.g, colour.b, colour.r, colour.g, colour.b)
            .additive(born, land)
    }
}

// ---------------------------------------------------------------------------
// The core — the light that builds and then detonates.
//
// A steady light is **not particles**: it is a shape, a position and an
// opacity. A handful of large still sprites reads better than a simulated one
// and costs a twentieth as much.
//
// The shape in time is the whole job here — small and dim through the charge,
// snapping open at the burst, then settling into the shine.
// ---------------------------------------------------------------------------

const core = () => {
    const layers = 8

    for (let i = 0; i < layers; i += 1) {
        const t = i / (layers - 1)
        const colour = rampAt(t * 0.7)
        // Overlapping large sprites need very low opacity: eight at 0.4 with
        // additive is one white disc, which is what the first port produced.
        const peak = baseOpacity * 0.5 * (1 - t * 0.55)
        const small = (40 + t * 90) / SOURCE
        const big = (150 + t * 320) / SOURCE

        sprite(GLOW, { origin: Origin.Centre })
            .fade(Ease.quadIn, 0, burstTime, 0, peak * 0.45)
            // The detonation: opacity and size both jump in 90ms. A burst is a
            // discontinuity — anything gradual here is a crescendo that fizzles.
            .fade(burstTime, burstTime + 90, peak * 0.45, peak * 1.6)
            .fade(Ease.quadOut, burstTime + 90, duration, peak * 1.6, peak * 0.8)
            .scale(Ease.quadIn, 0, burstTime, small * 0.5, small)
            .scale(Ease.quadOut, burstTime, burstTime + 260, small, big)
            .scale(Ease.quadInOut, burstTime + 260, duration, big, big * 0.88)
            .at(centre.x, centre.y)
            .color(0, 0, colour.r, colour.g, colour.b, colour.r, colour.g, colour.b)
            .additive(0, duration)
    }

    // The flare on top. `starflare` has rays of its own — structure the code
    // cannot draw with a gradient, which is exactly when a file beats a shape.
    sprite(FLARE, { origin: Origin.Centre })
        .fade(Ease.quadIn, 0, burstTime, 0, baseOpacity * 0.3)
        .fade(burstTime, burstTime + 90, baseOpacity * 0.3, baseOpacity * 0.95)
        .fade(Ease.quadOut, burstTime + 90, duration, baseOpacity * 0.95, baseOpacity * 0.5)
        .scale(Ease.quadIn, 0, burstTime, 60 / SOURCE, 130 / SOURCE)
        .scale(Ease.quadOut, burstTime, burstTime + 300, 130 / SOURCE, 330 / SOURCE)
        .scale(Ease.quadInOut, burstTime + 300, duration, 330 / SOURCE, 300 / SOURCE)
        .at(centre.x, centre.y)
        .color(0, 0, coreColour.r, coreColour.g, coreColour.b, coreColour.r, coreColour.g, coreColour.b)
        .additive(0, duration)
}

// ---------------------------------------------------------------------------
// Act two — the burst.
//
// One volley, every particle leaving at the same instant. This is the only
// layer that must not be spread out in time: a burst staggered over half a
// second is a fountain.
// ---------------------------------------------------------------------------

const explode = () => {
    for (let i = 0; i < burstCount; i += 1) {
        // Spread evenly around the circle rather than sampled at random, so no
        // wedge is left empty — with a few hundred particles, random clumps.
        const angle = (i / burstCount) * Math.PI * 2 + rng.between(-0.06, 0.06)

        // A handful lead by a few milliseconds. Exactly simultaneous reads as a
        // wipe; a few milliseconds of scatter reads as a shockwave.
        const t = burstTime + rng.between(0, 70)
        const life = rng.between(700, 1500)
        const end = Math.min(duration, t + life)

        const far = rng.between(1.1, 2.4)
        const toX = centre.x + Math.cos(angle) * reach * far
        const toY = centre.y + Math.sin(angle) * reach * far * 0.72

        const thickness = (rng.between(3, 9) / SOURCE)
        const length = thickness * stretch * rng.between(1, 1.8)
        const colour = rampAt(rng.between(0, 0.5))

        sprite(STREAK, { origin: Origin.Centre })
            .fade(t, t + 50, 0, baseOpacity * 1.2)
            .fade(Ease.quadIn, end - life * 0.5, end, baseOpacity * 1.2, 0)
            // quadOut — thrown things decelerate. It is the mirror of the
            // charge, and using the same curve for both would make the burst
            // read as more of the same instead of as a release.
            .move(Ease.quadOut, t, end, centre.x, centre.y, toX, toY)
            .scaleVec(Ease.quadOut, t, end, length * 0.3, thickness, length, thickness * 0.4)
            .rotate(t, t, angle, angle)
            .color(t, t, colour.r, colour.g, colour.b, colour.r, colour.g, colour.b)
            .additive(t, end)
    }
}

// ---------------------------------------------------------------------------
// The shockwave — one ring, expanding and gone.
//
// A ring of particles cannot rotate as an object, but it can *expand*, and a
// thin ring opening outward is the single clearest way to say that something
// broke at this instant.
// ---------------------------------------------------------------------------

const shockwave = () => {
    const count = 64

    for (let i = 0; i < count; i += 1) {
        const angle = (i / count) * Math.PI * 2
        const life = 620
        const end = Math.min(duration, burstTime + life)

        const from = 18
        const to = reach * 1.5
        const scale = rng.between(16, 30) / SOURCE

        sprite(GLOW, { origin: Origin.Centre })
            .fade(burstTime, burstTime + 40, 0, baseOpacity * 0.9)
            .fade(Ease.quadIn, burstTime + 40, end, baseOpacity * 0.9, 0)
            .move(Ease.quadOut, burstTime, end,
                  centre.x + Math.cos(angle) * from,
                  centre.y + Math.sin(angle) * from * 0.72,
                  centre.x + Math.cos(angle) * to,
                  centre.y + Math.sin(angle) * to * 0.72)
            // Shrinking as it spreads: a wave thins as it covers more ground,
            // and holding size reads as debris rather than as a front.
            .scale(Ease.quadOut, burstTime, end, scale * 1.6, scale * 0.3)
            .color(burstTime, burstTime,
                   coreColour.r, coreColour.g, coreColour.b,
                   coreColour.r, coreColour.g, coreColour.b)
            .additive(burstTime, end)
    }
}

// ---------------------------------------------------------------------------
// Act three — the shine.
//
// Slow drifting stars after the burst, so the clip settles instead of stopping.
// "Shine forever" is the line; ending on an empty frame contradicts it.
// ---------------------------------------------------------------------------

const shine = () => {
    const after = duration - burstTime
    if (after < 200) return

    const count = Math.max(10, Math.floor(burstCount * 0.35))
    for (let i = 0; i < count; i += 1) {
        const t = burstTime + (i / count) * after * 0.7
        const life = rng.between(700, after)
        const end = Math.min(duration, t + life)

        const angle = rng.unit() * Math.PI * 2
        const distance = rng.between(60, reach * 0.9)
        const x = centre.x + Math.cos(angle) * distance
        const y = centre.y + Math.sin(angle) * distance * 0.72

        const useStar = rng.unit() < 0.55
        const source = useStar ? STAR_SOURCE : SOURCE
        const scale = rng.between(14, 34) / source
        const colour = rampAt(rng.between(0, 0.7))
        const peak = baseOpacity * rng.between(0.4, 0.9)

        sprite(useStar ? STAR : GLOW, { origin: Origin.Centre })
            .fade(Ease.quadOut, t, t + (end - t) * 0.35, 0, peak)
            .fade(Ease.quadIn, t + (end - t) * 0.6, end, peak, 0)
            // Drifting outward a little: stars pinned in place read as dust on
            // the lens.
            .move(Ease.quadOut, t, end, x, y,
                  centre.x + Math.cos(angle) * distance * 1.25,
                  centre.y + Math.sin(angle) * distance * 1.25 * 0.72)
            .scale(Ease.quadOut, t, end, scale * 0.4, scale)
            .color(t, t, colour.r, colour.g, colour.b, colour.r, colour.g, colour.b)
            .additive(t, end)
    }
}

core()
charge()
shockwave()
explode()
shine()
