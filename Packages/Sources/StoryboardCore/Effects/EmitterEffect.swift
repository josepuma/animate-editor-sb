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
        public static let sprite = "sprite"

        public static let x = "x"
        public static let y = "y"
        public static let width = "width"
        public static let height = "height"

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
        public static let rotation = "rotation"
        public static let spin = "spin"

        public static let color = "color"
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
    }

    /// Ceiling on the particle count.
    ///
    /// Not a performance guess: the renderer holds 60fps at a little over two
    /// thousand sprites, and a `.osb` grows by roughly a line per command, so
    /// this is the point past which the result stops being usable in the game
    /// rather than just slow in the editor.
    public static let maximumCount = 2000

    public static let descriptor = EffectDescriptor(
        type: "emitter",
        name: "Emitter",
        category: "Particles",
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
            EffectParameter(
                id: Param.sprite,
                name: "Sprite",
                group: "Emission",
                defaultValue: .text("sb/particle.png"),
            ),

            // ── Position ────────────────────────────────────────────────────
            EffectParameter(
                id: Param.x,
                name: "X",
                group: "Position",
                defaultValue: .number(320),
                range: -107...747,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.y,
                name: "Y",
                group: "Position",
                defaultValue: .number(240),
                range: 0...480,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.width,
                name: "Width",
                group: "Position",
                defaultValue: .number(0),
                range: 0...854,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.height,
                name: "Height",
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
            EffectParameter(
                id: Param.color,
                name: "Colour",
                group: "Appearance",
                defaultValue: .color(.white),
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
        let filePath = context.text(Param.sprite)
        guard !filePath.isEmpty else { return [] }

        let originX = context.number(Param.x)
        let originY = context.number(Param.y)
        let halfWidth = context.number(Param.width) / 2
        let halfHeight = context.number(Param.height) / 2

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
        let rotationRandom = context.number(Param.rotation)
        let spin = context.number(Param.spin)

        let colour = context.color(Param.color)
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
            }

            let particleLife = max(1, life * (1 + particle.symmetric(lifeRandom)))
            let death = birth + particleLife

            let angle = (direction + particle.symmetric(spread)) * .pi / 180
            let speed = velocity * (1 + particle.symmetric(velocityRandom))
            // Velocity is authored per second; every time here is milliseconds.
            let vx = cos(angle) * speed / 1000
            let vy = sin(angle) * speed / 1000

            let startX = originX + particle.symmetric(halfWidth)
            let startY = originY + particle.symmetric(halfHeight)

            let scaleJitter = 1 + particle.symmetric(scaleRandom)
            let startScale = scaleStart * scaleJitter
            let endScale = scaleEnd * scaleJitter

            let startAngle = particle.symmetric(rotationRandom) * .pi / 180

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

            if fadeIn > 0 {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: fadeInEnd,
                    payload: .fade(start: 0, end: opacity),
                ))
            } else {
                // Without an explicit start the sprite would hold its default
                // opacity from the file's beginning, showing every particle
                // before its own birth.
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth,
                    payload: .fade(start: opacity, end: opacity),
                ))
            }

            if fadeOut > 0, fadeOutStart > fadeInEnd {
                commands.append(Command(
                    easing: .linear,
                    startTime: fadeOutStart,
                    endTime: death,
                    payload: .fade(start: opacity, end: 0),
                ))
            } else if fadeOut > 0 {
                // Fades that overlap: run one straight from the end of the
                // fade-in, rather than letting the pair fight over the middle.
                commands.append(Command(
                    easing: .linear,
                    startTime: fadeInEnd,
                    endTime: death,
                    payload: .fade(start: opacity, end: 0),
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
            if startScale != endScale {
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
            if colour != .white {
                commands.append(Command(
                    easing: .linear,
                    startTime: birth,
                    endTime: birth,
                    payload: .color(
                        startR: colour.r, startG: colour.g, startB: colour.b,
                        endR: colour.r, endG: colour.g, endB: colour.b,
                    ),
                ))
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

        return sprites
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
