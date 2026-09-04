import Foundation

/// A particle emitter.
///
/// Modelled on the emitters in After Effects and Particle Illusion, with one
/// constraint those tools do not have: osu! never simulates. Every particle is
/// a sprite whose whole life is written out as commands ahead of time, so each
/// trajectory has to be expressible as a closed curve. Gravity, drag, spread
/// and fade-over-life all are; collisions and turbulence are not, and so are
/// absent rather than approximated.
///
/// The other consequence is cost. A particle here is a sprite in a text file,
/// not a point in a simulation, so the count is a bounded total rather than a
/// rate — a few thousand sprites is a large storyboard, and five thousand a
/// second would be a file osu! will not open.
public struct EmitterEffect: Effect {
    public init() {}

    // ─── Parameter ids ───────────────────────────────────────────────────────
    //
    // Named constants because the same string is written in the declaration and
    // read during evaluation, and a typo in either compiles and silently yields
    // a default.

    public enum Param {
        public static let count = "count"
        public static let emission = "emission"
        public static let burstCount = "burstCount"
        public static let sprite = "sprite"
        public static let core = "core"
        public static let edge = "edge"
        public static let softness = "softness"

        /// Kept so presets written against them still place an emitter: the
        /// values are moved onto the transform when one is applied.
        public static let x = "x"
        public static let y = "y"
        public static let width = "width"
        public static let height = "height"
        public static let shape = "shape"
        public static let radial = "radial"
        public static let swirl = "swirl"
        public static let tilt = "tilt"
        public static let bands = "bands"

        public static let direction = "direction"
        public static let spread = "spread"
        public static let velocity = "velocity"
        public static let velocityRandom = "velocityRandom"

        public static let gravity = "gravity"
        public static let drag = "drag"

        public static let life = "life"
        public static let lifeRandom = "lifeRandom"
        public static let scaleStart = "scaleStart"
        public static let scaleEnd = "scaleEnd"
        public static let scaleRandom = "scaleRandom"
        public static let stretch = "stretch"
        public static let rotation = "rotation"
        public static let alignToMotion = "alignToMotion"
        public static let spin = "spin"

        public static let color = "color"
        public static let colorEnd = "colorEnd"
        public static let colorMid = "colorMid"
        public static let usesColorMid = "usesColorMid"
        public static let colorVariety = "colorVariety"
        public static let opacity = "opacity"
        public static let fadeIn = "fadeIn"
        public static let fadeOut = "fadeOut"
        public static let additive = "additive"
    }

    /// How particles are released over the effect's duration.
    public enum Emission: String, CaseIterable {
        /// All at once, at the start.
        case burst = "Burst"
        /// Spread evenly across the duration.
        case continuous = "Continuous"
        /// In clumps, with gaps between them.
        ///
        /// An even drip is right for fire and snow and wrong for anything that
        /// happens: lightning strikes two or three times in a moment and then
        /// stops. Spreading those strikes evenly turns an event into a metronome.
        case bursts = "Repeating Bursts"
    }

    /// Where inside the emitter a particle is born.
    ///
    /// Without this an emitter is always a rectangle, so a circle can only be
    /// faked — and a preset that promises a ring and emits a bar is a preset
    /// whose name lies. Width and height stay the extents in every case, so
    /// the same two numbers describe all four.
    public enum Shape: String, CaseIterable {
        /// Anywhere inside the box.
        case rectangle = "Rectangle"
        /// Anywhere inside the ellipse it contains.
        ///
        /// Sampled by area, not by picking a radius uniformly: a uniform radius
        /// crowds the centre, because the outer rings hold more space than the
        /// inner ones and get the same share of particles.
        case ellipse = "Ellipse"
        /// On the ellipse's edge — the ring.
        case ring = "Ring"
        /// A single point, whatever the extents say.
        ///
        /// Not the same as width and height at zero: it stays a point while
        /// those numbers are kept, so switching back restores the field that
        /// was already tuned.
        case point = "Point"
        /// Bands of a sphere: rings stacked by latitude.
        ///
        /// A sphere drawn as particles is a cloud; a sphere drawn as *rings* is
        /// a solid, because the bands are what the eye traces to read a surface
        /// curving away. Each band is narrower and leans harder the closer it
        /// sits to a pole, which is one circle seen at every angle at once.
        case sphere = "Sphere"
    }

    /// Where one particle is born, relative to the emitter's centre.
    static func spawnOffset(
        shape: Shape,
        halfWidth: Double,
        halfHeight: Double,
        bands: Int = 1,
        tilt: Double = 0,
        rng: inout EffectRandom,
    ) -> (x: Double, y: Double, phase: Double, tilt: Double) {
        switch shape {
        case .point:
            (0, 0, 0, tilt)

        case .rectangle:
            (rng.symmetric(halfWidth), rng.symmetric(halfHeight), 0, tilt)

        case .ring:
            {
                let angle = rng.between(0, 2 * .pi)
                return (cos(angle) * halfWidth, sin(angle) * halfHeight, angle, tilt)
            }()

        case .sphere:
            {
                // Which band, and how far up the sphere it sits. Latitude runs
                // −1 at the south pole to +1 at the north; the bands land at
                // the midpoints so none of them collapses onto a pole, where a
                // ring has no radius left to draw.
                let count = max(1, bands)
                let index = rng.integer(in: 0 ... (count - 1))
                let latitude = count == 1
                    ? 0
                    : (Double(index) + 0.5) / Double(count) * 2 - 1

                // The band's own circle: a slice through a sphere is a circle
                // whose radius follows the cosine of its latitude, which is
                // what makes the bands crowd towards the poles.
                let ringRadius = (1 - latitude * latitude).squareRoot()
                let angle = rng.between(0, 2 * .pi)

                // How far the sphere itself is turned: at 0 the bands are
                // seen edge-on and read as straight lines, and it is the lean
                // that opens them into the ellipses that describe a surface.
                // Bands near a pole are already almost face-on and open
                // furthest, which is what makes the top and bottom of a
                // wireframe globe read as circles.
                //
                // Floored, because a sphere with no lean is a stack of
                // horizontal lines — technically what zero degrees means, and
                // never what someone reaching for a sphere wants. A ring keeps
                // its honest flat reading; a sphere is a solid by definition.
                let openness = max(0.45, sin(min(tilt, 89) * .pi / 180))
                let bandOpening = openness * (0.35 + 0.65 * abs(latitude))

                return (
                    cos(angle) * halfWidth * ringRadius,
                    // The band's own height on the sphere, plus how far its
                    // ellipse reaches above and below that line.
                    //
                    // Height comes from latitude alone: a sphere is as tall as
                    // it is wide however it is turned, and squashing it by the
                    // lean — the right move for a single ring — collapses it
                    // into the disc it is meant not to be.
                    // Normalised against how far the whole set actually
                    // reaches, not against one band's worst case: a band's
                    // ellipse extends past its own latitude, so left unpaid it
                    // stretches the poles into an egg — and paid for band by
                    // band it squashes every other one flat.
                    (latitude + sin(angle) * ringRadius * bandOpening)
                        / Self.sphereReach(bands: count, opening: openness)
                        * halfHeight,
                    angle,
                    // Flat-on where the band opens widest, edge-on where it
                    // closes to a line.
                    min(89, 90 - bandOpening * 90)
                )
            }()

        case .ellipse:
            {
                let angle = rng.between(0, 2 * .pi)
                // The square root is what keeps the middle from clogging: area
                // grows with the square of the radius, so a uniform radius
                // gives the crowded centre and the roomy rim the same count.
                let radius = sqrt(rng.unit())
                return (
                    cos(angle) * radius * halfWidth,
                    sin(angle) * radius * halfHeight,
                    angle,
                    tilt,
                )
            }()
        }
    }

    /// How a ring tilted away from the viewer changes one particle.
    ///
    /// osu! has no 3D, but a ring seen at an angle is not just a squashed
    /// ellipse — that is the shape a *flat* ring would make. What sells the
    /// tilt is that each particle is affected differently by where it sits on
    /// the circle, and all three of these are readings of the same rotation:
    ///
    /// | | At the sides | At the top and bottom |
    /// |---|---|---|
    /// | Facing | Edge-on: narrow and tall | Flat-on: wide and short |
    /// | Distance | Level with the viewer | Far at the top, near at the bottom |
    ///
    /// Handing all three to `_V`, scale and opacity is 2D standing in for
    /// depth, and it costs nothing extra: the commands were being written
    /// anyway.
    ///
    /// - Parameters:
    ///   - phase: where on the circle the particle sits, in radians, measured
    ///     from the right and turning down the screen.
    ///   - tilt: how far the ring leans away, in degrees. 0 faces the viewer.
    static func perspective(phase: Double, tilt: Double) -> (
        stretch: Double, scale: Double, brightness: Double
    ) {
        guard tilt > 0 else { return (1, 1, 1) }

        let lean = cos(min(tilt, 89) * .pi / 180)

        // How much of the particle's own facing is turned away. At the sides
        // of the ring it is edge-on to the tilt and keeps its height; across
        // the top and bottom it lies flat and loses it.
        let facing = abs(sin(phase))
        let stretch = 1 - (1 - lean) * facing

        // Depth: −1 at the back of the ring, +1 at the front.
        //
        // The back is the *top* of the screen, because y grows downward here —
        // getting that sign wrong makes the far half the larger and brighter
        // one, which reads as a bowl rather than as a ring leaning away.
        let depth = sin(phase)
        let scale = 1 + depth * 0.28 * (1 - lean)
        let brightness = 1 + depth * 0.35 * (1 - lean)

        return (stretch, scale, brightness)
    }

    /// How far above the equator a sphere's bands actually reach, as a
    /// fraction of its radius.
    ///
    /// The outermost band sits high *and* opens upward, so the two add. Solved
    /// over the bands rather than assumed, because which one reaches furthest
    /// depends on how many there are: with few bands the top one sits well
    /// short of the pole and its opening still clears everything below.
    static func sphereReach(bands: Int, opening rawOpening: Double) -> Double {
        let opening = max(0.45, rawOpening)
        let count = max(1, bands)
        var reach = 1.0

        for index in 0 ..< count {
            let latitude = count == 1
                ? 0
                : (Double(index) + 0.5) / Double(count) * 2 - 1
            let ringRadius = (1 - latitude * latitude).squareRoot()
            let bandOpening = opening * (0.35 + 0.65 * abs(latitude))
            reach = max(reach, abs(latitude) + ringRadius * bandOpening)
        }

        return reach
    }

    /// Which way is "away from the centre", in degrees, for a particle at
    /// `offset`.
    ///
    /// Not the angle of the point itself: on a stretched ellipse the outward
    /// normal and the line back to the centre are different directions, and
    /// using the latter makes a flattened ring spray sideways along its own
    /// edge instead of away from it. The normal of `(x/a)² + (y/b)² = 1` is
    /// `(x/a², y/b²)`, which is what this is.
    static func outwardAngle(
        _ offset: (x: Double, y: Double, phase: Double, tilt: Double),
        halfWidth: Double,
        halfHeight: Double,
    ) -> Double {
        let nx = halfWidth > 0 ? offset.x / (halfWidth * halfWidth) : offset.x
        let ny = halfHeight > 0 ? offset.y / (halfHeight * halfHeight) : offset.y

        // A particle exactly at the centre has no outward direction, so it gets
        // one at random rather than all of them piling onto the same axis.
        guard nx != 0 || ny != 0 else { return 0 }

        // Quarter turn back, because Direction is not the mathematical angle.
        //
        // `Direction: 270` means *up* in this emitter, where `cos`/`sin` would
        // call up −90. The two conventions are a quarter turn apart, and adding
        // a raw `atan2` to a Direction crossed them: a "radial" ring threw its
        // particles **along** the rim while the parameter said outward. Every
        // preset using Radial was ninety degrees out.
        return atan2(ny, nx) * 180 / .pi + 90
    }

    /// Ceiling on the particle count.
    ///
    /// Not a performance guess: the renderer holds 60fps at a little over two
    /// thousand sprites, and a `.osb` grows by roughly a line per command, so
    /// this is the point past which the result stops being usable in the game
    /// rather than just slow in the editor.
    public static let maximumCount = 2000

    /// Path of the particle an emitter starts with.
    ///
    /// Mirrors `BuiltInTextures.particle`, spelled out here because
    /// `StoryboardCore` sits below the renderer and cannot import it. A test
    /// checks the two agree.
    public static let defaultSpritePath = BuiltInSprite.soft

    public static let descriptor = EffectDescriptor(
        type: "emitter",
        name: "Emitter",
        category: .generate,
        systemImage: "sparkles",
        parameters: [
            // ── Emission ────────────────────────────────────────────────────
            EffectParameter(
                id: Param.count,
                name: "Particles",
                group: "Emission",
                defaultValue: .integer(120),
                range: 1...Double(maximumCount),
                step: 1,
            ),
            EffectParameter(
                id: Param.emission,
                name: "Emission",
                group: "Emission",
                defaultValue: .choice(Emission.continuous.rawValue),
                options: Emission.allCases.map(\.rawValue),
            ),
            // Stays `.text` rather than a menu of the built-in shapes: the
            // point is that a beatmap's own image can be typed in, and a choice
            // parameter can only hold what it declares. The inspector offers
            // the shapes alongside the field.
            EffectParameter(
                id: Param.shape,
                name: "Shape",
                group: "Emission",
                defaultValue: .choice(Shape.rectangle.rawValue),
                options: Shape.allCases.map(\.rawValue),
            ),
            // Turns "outward" into "around".
            //
            // The tangent to a circle is its normal turned a quarter turn, so
            // this is that quarter turn made adjustable: 0 goes straight out,
            // 90 runs along the rim, and everything between is a spiral. A ring
            // of particles cannot rotate as an object — each one is born where
            // it is born — so travelling *along* the rim is the only way energy
            // circles a ring in this format.
            EffectParameter(
                id: Param.swirl,
                name: "Swirl",
                group: "Emission",
                defaultValue: .number(0),
                range: -90...90,
                step: 1,
                unit: "°",
                presentation: .slider,
                shownWhen: .init(parameter: Param.radial, isAnyOf: ["true"]),
            ),
            // Zero by default: a flat ring is the honest reading of the
            // extents, and perspective is something asked for.
            EffectParameter(
                id: Param.tilt,
                name: "Tilt",
                group: "Emission",
                defaultValue: .number(0),
                range: 0...85,
                step: 1,
                unit: "°",
            ),
            // Only read by the sphere: everything else has one band by
            // definition. Kept low — each band is a line the eye follows, and
            // past a dozen they stop reading as separate.
            EffectParameter(
                id: Param.bands,
                name: "Bands",
                group: "Emission",
                defaultValue: .integer(7),
                range: 1...16,
                step: 1,
            ),
            // Off by default, because it only means anything once the shape is
            // round: on a rectangle "outward" has no centre to point away from
            // that Direction does not already say better.
            EffectParameter(
                id: Param.radial,
                name: "Radial",
                group: "Emission",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.burstCount,
                name: "Bursts",
                group: "Emission",
                defaultValue: .integer(3),
                range: 1...40,
                step: 1,
            ),
            EffectParameter(
                id: Param.sprite,
                name: "Sprite",
                group: "Emission",
                // Empty by default, so the three shape parameters below decide
                // what a particle looks like. A path here overrides them —
                // that is the escape hatch for anything code cannot draw.
                defaultValue: .text(""),
            ),

            // ── Particle Shape ──────────────────────────────────────────────
            //
            // "Particle Shape" rather than "Shape": `Param.shape` above already
            // means the *emission area's* shape, and two things with one name
            // in one panel is a reader having to guess which is which.
            //
            // Three numbers instead of a menu of nine textures.
            //
            // The fixed list was the one thing in this system a user could not
            // compose: every other parameter is an axis they combine freely,
            // while the particle's own form could only be widened by editing
            // the app. That is the line between an editor and a catalogue.
            //
            // And most of those nine were the same radial gradient with
            // different numbers — a soft dot, a tight glow, a flat disc and a
            // ring differ only in how bright the middle is and where the edge
            // falls. Made parametric, everything *between* them opens up too,
            // which is where a bokeh circle lives.
            EffectParameter(
                id: Param.core,
                name: "Core",
                group: "Particle Shape",
                // Solid, which is what a plain particle is. Below one the
                // middle dims — at zero it is a ring, and around 0.6 it is the
                // defocused highlight a lens makes, dimmer inside than at its
                // own rim.
                defaultValue: .number(1),
                range: 0...1,
                step: 0.02,
                presentation: .slider,
                shownWhen: .init(parameter: Param.sprite, isAnyOf: [""]),
            ),
            EffectParameter(
                id: Param.edge,
                name: "Edge",
                group: "Particle Shape",
                // Where the brightest ring sits. Near zero the particle is a
                // point of light; near one it is a disc with a defined rim.
                defaultValue: .number(0.35),
                range: 0.02...1,
                step: 0.02,
                unit: "×",
                presentation: .slider,
                shownWhen: .init(parameter: Param.sprite, isAnyOf: [""]),
            ),
            EffectParameter(
                id: Param.softness,
                name: "Softness",
                group: "Particle Shape",
                // How much of the radius *left over* past the edge the fade
                // uses. A fraction rather than a distance, or the two fight
                // over the same space and a rim near the outside silently
                // clips its own falloff.
                defaultValue: .number(1),
                range: 0...1,
                step: 0.02,
                presentation: .slider,
                shownWhen: .init(parameter: Param.sprite, isAnyOf: [""]),
            ),

            // ── Position ────────────────────────────────────────────────────
            //
            // X and Y are not declared here: position lives on the node's
            // transform, where it can be keyframed. Declaring them in both
            // places would give one property two homes and let them disagree.
            // Named for what they are — the area particles are born across —
            // rather than "Width" and "Height", which sit next to a "Sprite"
            // parameter and read as the size of that image. Zero emits every
            // particle from a single point.
            EffectParameter(
                id: Param.width,
                name: "Emitter Width",
                group: "Position",
                defaultValue: .number(0),
                range: 0...854,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.height,
                name: "Emitter Height",
                group: "Position",
                defaultValue: .number(0),
                range: 0...480,
                step: 1,
                unit: "px",
            ),

            // ── Direction ───────────────────────────────────────────────────
            EffectParameter(
                id: Param.direction,
                name: "Direction",
                group: "Direction",
                defaultValue: .number(270),
                range: 0...360,
                step: 1,
                unit: "°",
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.spread,
                name: "Spread",
                group: "Direction",
                defaultValue: .number(30),
                range: 0...180,
                step: 1,
                unit: "°",
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.velocity,
                name: "Velocity",
                group: "Direction",
                defaultValue: .number(120),
                range: 0...2000,
                step: 5,
                unit: "px/s",
            ),
            EffectParameter(
                id: Param.velocityRandom,
                name: "Velocity Random",
                group: "Direction",
                defaultValue: .number(0.2),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),

            // ── Physics ─────────────────────────────────────────────────────
            EffectParameter(
                id: Param.gravity,
                name: "Gravity",
                group: "Physics",
                defaultValue: .number(0),
                range: -2000...2000,
                step: 10,
                unit: "px/s²",
            ),
            EffectParameter(
                id: Param.drag,
                name: "Drag",
                group: "Physics",
                defaultValue: .number(0),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),

            // ── Particle ────────────────────────────────────────────────────
            EffectParameter(
                id: Param.life,
                name: "Life",
                group: "Particle",
                defaultValue: .number(1200),
                range: 50...20_000,
                step: 50,
                unit: "ms",
            ),
            EffectParameter(
                id: Param.lifeRandom,
                name: "Life Random",
                group: "Particle",
                defaultValue: .number(0.2),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.scaleStart,
                name: "Scale Start",
                group: "Particle",
                defaultValue: .number(1),
                range: 0...20,
                step: 0.05,
            ),
            EffectParameter(
                id: Param.scaleEnd,
                name: "Scale End",
                group: "Particle",
                defaultValue: .number(1),
                range: 0...20,
                step: 0.05,
            ),
            EffectParameter(
                id: Param.scaleRandom,
                name: "Scale Random",
                group: "Particle",
                defaultValue: .number(0.2),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            // Stretch along the direction of travel, using `_V`.
            //
            // Uniform scale is the wrong tool for anything that moves fast: a
            // raindrop is long and thin, and scaling it up to get the length
            // gives it the width too — the drops end up as grey bars. `_V`
            // scales the axes separately, which is what osu! provides it for.
            EffectParameter(
                id: Param.stretch,
                name: "Stretch",
                group: "Particle",
                defaultValue: .number(1),
                range: 0.1...20,
                step: 0.1,
            ),
            EffectParameter(
                id: Param.rotation,
                name: "Rotation Random",
                group: "Particle",
                defaultValue: .number(0),
                range: 0...360,
                step: 1,
                unit: "°",
                presentation: .slider,
            ),
            // Point the sprite where the particle is going.
            //
            // Without this, rotation is pure noise and a shaped texture faces a
            // random way regardless of travel: a raindrop falling at an angle
            // is drawn upright, sliding sideways through its own path. Round
            // particles do not care, which is why it is off by default.
            EffectParameter(
                id: Param.alignToMotion,
                name: "Align to Motion",
                group: "Particle",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.spin,
                name: "Spin",
                group: "Particle",
                defaultValue: .number(0),
                range: -1440...1440,
                step: 10,
                unit: "°/s",
            ),

            // ── Appearance ──────────────────────────────────────────────────
            // Colour over life, which is most of what makes a particle field
            // read as a material rather than as dots. Real fire is white at its
            // base, orange as it rises and red as it cools; one flat colour
            // looks like moving specks whatever the sprite behind it is.
            EffectParameter(
                id: Param.color,
                name: "Colour Start",
                group: "Appearance",
                defaultValue: .color(.white),
            ),
            EffectParameter(
                id: Param.colorEnd,
                name: "Colour End",
                group: "Appearance",
                defaultValue: .color(.white),
            ),
            EffectParameter(
                id: Param.usesColorMid,
                name: "Use Midpoint",
                group: "Appearance",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.colorMid,
                name: "Colour Mid",
                group: "Appearance",
                defaultValue: .color(.white),
                shownWhen: .init(parameter: Param.usesColorMid, isAnyOf: ["true"]),
            ),
            // How far each particle's colour strays from the ramp.
            //
            // The ramp runs over a particle's life, so on its own every
            // particle is the same colour at the same moment. That is right for
            // fire, where the whole field cools together, and wrong for
            // confetti, which is many colours *at once* — one ramp cannot say
            // that, so the variety has to be per particle.
            EffectParameter(
                id: Param.colorVariety,
                name: "Colour Variety",
                group: "Appearance",
                defaultValue: .number(0),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.opacity,
                name: "Opacity",
                group: "Appearance",
                defaultValue: .number(1),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.fadeIn,
                name: "Fade In",
                group: "Appearance",
                defaultValue: .number(0.15),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.fadeOut,
                name: "Fade Out",
                group: "Appearance",
                defaultValue: .number(0.35),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.additive,
                name: "Additive",
                group: "Appearance",
                defaultValue: .toggle(false),
            ),
        ],
    )

    /// How many straight segments a particle's path is cut into.
    ///
    /// A `_M` command interpolates in a straight line, so curved motion has to
    /// be approximated by pieces. Eight is where the arc of a falling particle
    /// stops reading as a bend: fewer and gravity looks like a hinge, more and
    /// the command count grows for a difference nobody sees.
    private static let pathSegments = 8

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let count = min(max(context.integer(Param.count), 0), Self.maximumCount)
        guard count > 0, context.duration > 0 else { return [] }

        let emission = Emission(rawValue: context.choice(Param.emission)) ?? .continuous
        let burstCount = max(1, context.integer(Param.burstCount))
        // A path wins when there is one — that is the escape hatch for shapes
        // code cannot draw, which is why the texture pack exists. Otherwise the
        // particle is built from its three numbers.
        let chosen = context.text(Param.sprite)
        let filePath = chosen.isEmpty
            ? BuiltInSprite.particle(
                core: context.number(Param.core),
                edge: context.number(Param.edge),
                falloff: context.number(Param.softness),
            )
            : chosen
        guard !filePath.isEmpty else { return [] }

        // Particles are emitted around the canvas centre; the clip's transform
        // carries the whole field from there. Reading it here as well would
        // apply the same movement twice.
        let originX = TransformProperty.x.defaultValue
        let originY = TransformProperty.y.defaultValue
        let halfWidth = context.number(Param.width) / 2
        let halfHeight = context.number(Param.height) / 2
        let shape = Shape(rawValue: context.choice(Param.shape)) ?? .rectangle
        let radial = context.toggle(Param.radial)
        let swirl = context.number(Param.swirl)
        let tilt = context.number(Param.tilt)
        let bands = context.integer(Param.bands)

        // A ring that leans away is shorter on screen, by the cosine of the
        // lean. Turning the particles without shortening the circle they sit on
        // is half a perspective: the pieces face away while the outline stays
        // as round as it was, which reads as a bug rather than as depth.
        //
        // A sphere works out its own vertical placement band by band, so the
        // emitter-wide squash would count the same lean twice.
        let leanHeight = shape == .sphere
            ? halfHeight
            : halfHeight * cos(min(tilt, 89) * .pi / 180)

        let direction = context.number(Param.direction)
        let spread = context.number(Param.spread)
        let velocity = context.number(Param.velocity)
        let velocityRandom = context.number(Param.velocityRandom)

        let gravity = context.number(Param.gravity)
        let drag = context.number(Param.drag)

        let life = context.number(Param.life)
        let lifeRandom = context.number(Param.lifeRandom)

        let scaleStart = context.number(Param.scaleStart)
        let scaleEnd = context.number(Param.scaleEnd)
        let scaleRandom = context.number(Param.scaleRandom)
        let stretch = context.number(Param.stretch)
        let rotationRandom = context.number(Param.rotation)
        let alignToMotion = context.toggle(Param.alignToMotion)
        let spin = context.number(Param.spin)

        let colour = context.color(Param.color)
        let colourEnd = context.color(Param.colorEnd)
        let colourMid = context.color(Param.colorMid)
        let usesMid = context.toggle(Param.usesColorMid)
        let colourVariety = context.number(Param.colorVariety)
        let opacity = context.number(Param.opacity)
        let fadeIn = context.number(Param.fadeIn)
        let fadeOut = context.number(Param.fadeOut)
        let additive = context.toggle(Param.additive)

        var sprites: [StoryboardSprite] = []
        sprites.reserveCapacity(count)

        for index in 0..<count {
            // A stream per particle, so raising the count adds particles
            // instead of reshuffling the ones already placed.
            var particle = rng.stream(index)

            let birth: Double = switch emission {
            case .burst: 0
            case .continuous:
                // Spread across the duration by index rather than at random:
                // a random release makes a continuous emitter clump, which
                // reads as a stuttering emitter rather than a steady one.
                count == 1 ? 0 : context.duration * Double(index) / Double(count)
            case .bursts:
                // Particles are dealt round-robin into `burstCount` groups, so
                // each group fires together and the groups are spread across
                // the duration. Dealing them in blocks instead would make the
                // first burst the first N particles, and every burst would draw
                // from a different part of the random stream — the strikes
                // would not look like siblings.
                context.duration * Double(index % burstCount) / Double(burstCount)
            }

            let particleLife = max(1, life * (1 + particle.symmetric(lifeRandom)))
            let death = birth + particleLife

            // Position first, because a radial emitter takes its direction
            // from where the particle landed.
            let offset = Self.spawnOffset(
                shape: shape,
                halfWidth: halfWidth,
                halfHeight: leanHeight,
                bands: bands,
                tilt: tilt,
                rng: &particle,
            )
            let startX = originX + offset.x
            let startY = originY + offset.y

            // 2D standing in for depth: how this particle is turned, how far
            // away it is, and how brightly that reads.
            let view = Self.perspective(phase: offset.phase, tilt: offset.tilt)

            // Outward from the emitter's centre, with Direction becoming a
            // rotation of that fan rather than the fan itself — so a ring can
            // still be tilted, and Spread still opens it.
            let baseDegrees: Double = if radial {
                // Swirl rides on the outward angle, because the tangent is
                // defined against it: without a centre to be "out" from, there
                // is nothing to turn a quarter of the way from either.
                Self.outwardAngle(offset, halfWidth: halfWidth, halfHeight: leanHeight)
                    + direction + swirl
            } else {
                direction
            }
            let angle = (baseDegrees + particle.symmetric(spread)) * .pi / 180
            let speed = velocity * (1 + particle.symmetric(velocityRandom))
            // Velocity is authored per second; every time here is milliseconds.
            let vx = cos(angle) * speed / 1000
            let vy = sin(angle) * speed / 1000

            // Multiplied rather than replaced: the emitter's scale is a
            // property of the emitter, and each particle keeps its own life.
            let scaleJitter = (1 + particle.symmetric(scaleRandom)) * view.scale
            let startScale = scaleStart * scaleJitter
            let endScale = scaleEnd * scaleJitter

            // The built-in shapes are drawn pointing up, so "aligned" means the
            // sprite's up axis follows the velocity — a quarter turn off the
            // travel angle itself.
            let alignment = alignToMotion ? angle - .pi / 2 : 0
            let startAngle = alignment + particle.symmetric(rotationRandom) * .pi / 180

            var commands: [Command] = []

            // ── Motion ──────────────────────────────────────────────────────
            // Sampled into straight segments because `_M` cannot curve. With
            // no gravity and no drag the path is already straight, so one
            // command carries it and the file stays small.
            let segments = (gravity == 0 && drag == 0) ? 1 : Self.pathSegments
            var previous = position(
                atLocalTime: 0,
                startX: startX, startY: startY,
                vx: vx, vy: vy,
                gravity: gravity, drag: drag,
            )
            for segment in 0..<segments {
                let from = particleLife * Double(segment) / Double(segments)
                let to = particleLife * Double(segment + 1) / Double(segments)
                let next = position(
                    atLocalTime: to,
                    startX: startX, startY: startY,
                    vx: vx, vy: vy,
                    gravity: gravity, drag: drag,
                )
                commands.append(Command(
                    easing: .linear,
                    startTime: birth + from,
                    endTime: birth + to,
                    payload: .move(
                        startX: previous.x, startY: previous.y,
                        endX: next.x, endY: next.y,
                    ),
                ))
                previous = next
            }

            // ── Fade ────────────────────────────────────────────────────────
            // Split into in, hold and out so a particle that fades at both ends
            // does not need the resolver to blend overlapping commands.
            let fadeInEnd = birth + particleLife * min(fadeIn, 1)
            let fadeOutStart = death - particleLife * min(fadeOut, 1)

            // Depth reads as brightness as much as it does as size: the far
            // side of a tilted ring is dimmer, and without that the two halves
            // look like one flat band whatever their scale says.
            let particleOpacity = min(1, opacity * view.brightness)

            if fadeIn > 0 {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: fadeInEnd,
                    payload: .fade(start: 0, end: particleOpacity),
                ))
            } else {
                // Without an explicit start the sprite would hold its default
                // opacity from the file's beginning, showing every particle
                // before its own birth.
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth,
                    payload: .fade(start: particleOpacity, end: particleOpacity),
                ))
            }

            if fadeOut > 0, fadeOutStart > fadeInEnd {
                commands.append(Command(
                    easing: .linear,
                    startTime: fadeOutStart,
                    endTime: death,
                    payload: .fade(start: particleOpacity, end: 0),
                ))
            } else if fadeOut > 0 {
                // Fades that overlap: run one straight from the end of the
                // fade-in, rather than letting the pair fight over the middle.
                commands.append(Command(
                    easing: .linear,
                    startTime: fadeInEnd,
                    endTime: death,
                    payload: .fade(start: particleOpacity, end: 0),
                ))
            } else {
                commands.append(Command(
                    easing: .linear,
                    startTime: death,
                    endTime: death,
                    payload: .fade(start: 0, end: 0),
                ))
            }

            // ── Scale ───────────────────────────────────────────────────────
            //
            // `_V` only when the axes differ: it costs the same as `_S` but
            // writes twice the numbers, and a storyboard is a text file.
            // The emitter's own stretch, times what the tilt does to this
            // particular particle: at the sides of a leaning ring a particle is
            // edge-on and keeps its height, across the top and bottom it lies
            // flat and loses it.
            let particleStretch = stretch * view.stretch

            if particleStretch != 1 {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: startScale == endScale ? birth : death,
                    payload: .vectorScale(
                        startX: startScale,
                        startY: startScale * particleStretch,
                        endX: endScale,
                        endY: endScale * particleStretch,
                    ),
                ))
            } else if startScale != endScale {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: death,
                    payload: .scale(start: startScale, end: endScale),
                ))
            } else if startScale != 1 {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth,
                    payload: .scale(start: startScale, end: startScale),
                ))
            }

            // ── Rotation ────────────────────────────────────────────────────
            let endAngle = startAngle + spin * particleLife / 1000 * .pi / 180
            if startAngle != 0 || endAngle != startAngle {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: endAngle == startAngle ? birth : death,
                    payload: .rotate(start: startAngle, end: endAngle),
                ))
            }

            // ── Colour ──────────────────────────────────────────────────────
            //
            // Each particle's own shift through hue, so a field can be many
            // colours at the same instant rather than one colour moving
            // through time.
            let shift = particle.symmetric(colourVariety)
            let colour = colour.varied(by: shift)
            let colourMid = colourMid.varied(by: shift)
            let colourEnd = colourEnd.varied(by: shift)

            //
            // `_C` interpolates between two colours on its own, so a start and
            // an end cost a single command. A midpoint costs a second, which is
            // why it is opt-in: every command here is multiplied by the
            // particle count in the exported file.
            //
            // Nothing is written when the whole ramp is white, since white is
            // what a sprite draws as untinted.
            if usesMid {
                let half = birth + particleLife / 2
                if colour != colourMid {
                    commands.append(colourCommand(from: colour, to: colourMid, start: birth, end: half))
                } else if colour != .white {
                    commands.append(colourCommand(from: colour, to: colour, start: birth, end: birth))
                }
                if colourMid != colourEnd {
                    commands.append(colourCommand(from: colourMid, to: colourEnd, start: half, end: death))
                }
            } else if colour != colourEnd {
                commands.append(colourCommand(from: colour, to: colourEnd, start: birth, end: death))
            } else if colour != .white {
                // A constant tint: held from birth, so it applies for the whole
                // life without a second command to end it.
                commands.append(colourCommand(from: colour, to: colour, start: birth, end: birth))
            }

            if additive {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: death,
                    payload: .parameter(.additive),
                ))
            }

            sprites.append(StoryboardSprite(
                id: "\(context.idPrefix)/p\(index)",
                layer: context.node.layer,
                origin: .centre,
                filePath: filePath,
                defaultX: startX,
                defaultY: startY,
                commands: commands,
            ))
        }

        // Far side first.
        //
        // Draw order is the one depth cue a storyboard has, and without it a
        // particle at the back of the ring can land on top of one at the
        // front — which reads as flat however carefully the rest is scaled.
        // Only worth doing on a tilted ring: with no tilt every particle is
        // the same distance away, and reordering would just cost the emitter
        // its file order for nothing.
        if shape == .sphere || (tilt > 0 && (shape == .ring || shape == .ellipse)) {
            sprites.sort { a, b in a.defaultY < b.defaultY }
        }

        return sprites
    }

    private func colourCommand(
        from: EffectColor,
        to: EffectColor,
        start: Double,
        end: Double,
    ) -> Command {
        Command(
            easing: .linear,
            startTime: start,
            endTime: end,
            payload: .color(
                startR: from.r, startG: from.g, startB: from.b,
                endR: to.r, endG: to.g, endB: to.b,
            ),
        )
    }

    /// Where a particle is `time` milliseconds after its birth.
    ///
    /// Drag is applied as exponential decay on velocity, which keeps the path a
    /// closed expression — a per-step simulation would have no way back to the
    /// handful of commands a storyboard can hold.
    private func position(
        atLocalTime time: Double,
        startX: Double,
        startY: Double,
        vx: Double,
        vy: Double,
        gravity: Double,
        drag: Double,
    ) -> (x: Double, y: Double) {
        let g = gravity / 1_000_000  // px/s² → px/ms²

        guard drag > 0 else {
            return (
                x: startX + vx * time,
                y: startY + vy * time + 0.5 * g * time * time
            )
        }

        // Velocity decays as v·e^(−kt); distance is its integral.
        let k = drag / 200
        let decay = (1 - exp(-k * time)) / k
        return (
            x: startX + vx * decay,
            y: startY + vy * decay + 0.5 * g * time * time
        )
    }
}
